import Cocoa
import Carbon
import UserNotifications

/// 检测 Accessibility API 是否真正可用
func isAccessibilityActuallyWorking() -> Bool {
    guard AXIsProcessTrusted() else { return false }
    guard let dockApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
        return false
    }
    let dockRef = AXUIElementCreateApplication(dockApp.processIdentifier)
    var value: AnyObject?
    let result = AXUIElementCopyAttributeValue(dockRef, kAXChildrenAttribute as CFString, &value)
    return result == .success
}

// Global callback function for CGEventTap
private func globalEventCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo = userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let monitor = Unmanaged<DockMonitor>.fromOpaque(userInfo).takeUnretainedValue()

    // 处理 tap 超时被系统暂时禁用的情况：立即重新启用，而不是销毁 tap
    if type == .tapDisabledByTimeout {
        LogService.shared.log(level: .warning, category: "DockMonitor", message: "[回调] 检测到 tapDisabledByTimeout，正在重新启用 tap")
        if let tap = monitor.eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passUnretained(event)
    }

    if type == .tapDisabledByUserInput {
        if let tap = monitor.eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passUnretained(event)
    }

    // 检查 tap 是否仍然处于启用状态，如果被意外禁用则重新激活
    if let tap = monitor.eventTap, !CGEvent.tapIsEnabled(tap: tap) {
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    let consumed = monitor.handleEvent(proxy: proxy, type: type, event: event)
    return consumed ? nil : Unmanaged.passUnretained(event)
}

/// Monitors Dock icon clicks
class DockMonitor: ObservableObject {
    static let shared = DockMonitor()

    private var currentFrontmostPID: pid_t?
    private var currentFrontmostName: String?
    var eventTap: CFMachPort?  // internal 访问级别，供回调函数使用
    private var runLoopSource: CFRunLoopSource?
    private var permissionCheckTimer: Timer?
    private var lastPermissionState: Bool = false  // 记录上次权限状态，用于检测变化

    /// 权限和功能是否完全可用
    @Published var isFullyFunctional: Bool = false

    private init() {
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            currentFrontmostPID = frontApp.processIdentifier
            currentFrontmostName = frontApp.localizedName
        }

        startWorkspaceMonitoring()
        tryStartEventTap()
        startPermissionCheckTimer()
    }

    deinit {
        permissionCheckTimer?.invalidate()
        stopEventTap()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    private func startPermissionCheckTimer() {
        let trusted = AXIsProcessTrusted()
        let interval: TimeInterval = trusted ? 5.0 : 1.0
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.checkPermissionState()
        }
        lastPermissionState = trusted
        checkPermissionState()
        LogService.shared.log(category: "DockMonitor", message: "[定时器] 已启动，间隔 \(interval) 秒，权限信任: \(trusted ? "是" : "否")")
    }

    private func checkPermissionState() {
        let trusted = AXIsProcessTrusted()
        let apiWorking = isAccessibilityActuallyWorking()
        LogService.shared.log(category: "DockMonitor", message: "[定时器检查] AXIsProcessTrusted: \(trusted ? "是" : "否"), API实际可用: \(apiWorking ? "是" : "否"), eventTap: \(eventTap != nil ? "存在" : "不存在")")

        // 只要系统信任此进程，并且 eventTap 正常建立，功能即视为可用
        isFullyFunctional = trusted && (eventTap != nil)

        // 检测系统权限状态变化（基于 AXIsProcessTrusted，避免因 Dock 繁忙引发误判）
        if trusted != lastPermissionState {
            if trusted {
                sendNotification(title: L10n.permissionGrantedNotificationTitle, body: L10n.permissionGrantedNotificationBody)
            } else {
                sendNotification(title: L10n.permissionRevoked, body: L10n.permissionRevokedMessage)
            }
            lastPermissionState = trusted
            adjustTimerInterval()
        }

        if trusted {
            if eventTap == nil {
                LogService.shared.log(category: "DockMonitor", message: "[定时器检查] 权限正常，尝试启动 eventTap")
                tryStartEventTap()
            } else if let tap = eventTap, !CGEvent.tapIsEnabled(tap: tap) {
                LogService.shared.log(category: "DockMonitor", message: "[定时器检查] 权限正常但 eventTap 被禁用，重新启用")
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        } else if eventTap != nil {
            // 系统权限真正被撤销时才停止 eventTap
            LogService.shared.log(level: .warning, category: "DockMonitor", message: "[定时器检查] 系统权限已撤销，停止 eventTap")
            stopEventTap()
        }
    }

    private func sendNotification(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if granted {
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                content.sound = .default

                let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
                center.add(request)
            }
        }
    }

    private func adjustTimerInterval() {
        permissionCheckTimer?.invalidate()
        let interval: TimeInterval = lastPermissionState ? 5.0 : 1.0
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.checkPermissionState()
        }
        LogService.shared.log(category: "DockMonitor", message: "[定时器] 间隔调整为 \(interval) 秒")
    }

    private func stopEventTap() {
        LogService.shared.log(category: "DockMonitor", message: "[stopEventTap] 开始停止，eventTap: \(eventTap != nil ? "存在" : "不存在")")
        guard let tap = eventTap else {
            LogService.shared.log(category: "DockMonitor", message: "[stopEventTap] eventTap 为空，跳过")
            return
        }

        CGEvent.tapEnable(tap: tap, enable: false)
        LogService.shared.log(category: "DockMonitor", message: "[stopEventTap] 已禁用 tap")

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
            LogService.shared.log(category: "DockMonitor", message: "[stopEventTap] 已移除 runLoopSource")
        }

        eventTap = nil
        LogService.shared.log(category: "DockMonitor", message: "[stopEventTap] 完成")
    }

    /// 当 CGEventTap 被系统禁用时调用（权限被撤销或超时）
    func handleTapDisabled() {
        LogService.shared.log(level: .warning, category: "DockMonitor", message: "[handleTapDisabled] 被调用")
        DispatchQueue.main.async { [weak self] in
            LogService.shared.log(category: "DockMonitor", message: "[handleTapDisabled] 主线程执行 stopEventTap")
            self?.stopEventTap()
        }
    }

    private func startWorkspaceMonitoring() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            self,
            selector: #selector(appActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    @objc private func appActivated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }
        currentFrontmostPID = app.processIdentifier
        currentFrontmostName = app.localizedName
    }

    private func tryStartEventTap() {
        guard AXIsProcessTrusted() else { return }

        if let tap = eventTap {
            if !CGEvent.tapIsEnabled(tap: tap) {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return
        }
        startEventTap()
    }

    private func startEventTap() {
        LogService.shared.log(category: "DockMonitor", message: "[startEventTap] 开始创建 eventTap")
        let eventMask = (1 << CGEventType.leftMouseDown.rawValue)
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: globalEventCallback,
            userInfo: selfPointer
        ) else {
            LogService.shared.log(level: .error, category: "DockMonitor", message: "[startEventTap] 无法创建 CGEventTap")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)

        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            LogService.shared.log(category: "DockMonitor", message: "[startEventTap] eventTap 创建成功并已启用")
        }
    }

    /// Get the name and URL of the app whose Dock icon is at the given click location
    private func getAppInfoAtDockLocation(_ clickPoint: CGPoint) -> (title: String, urlString: String?)? {
        guard let dockApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            return nil
        }

        let dockPID = dockApp.processIdentifier
        let dockAppRef = AXUIElementCreateApplication(dockPID)
        AXUIElementSetMessagingTimeout(dockAppRef, 0.05)

        var childrenValue: AnyObject?
        let childrenResult = AXUIElementCopyAttributeValue(dockAppRef, kAXChildrenAttribute as CFString, &childrenValue)

        guard childrenResult == .success, let children = childrenValue as? [AXUIElement] else {
            return nil
        }

        for child in children {
            var roleValue: AnyObject?
            AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleValue)

            guard let role = roleValue as? String, role == kAXListRole as String else {
                continue
            }

            var itemsValue: AnyObject?
            let itemsResult = AXUIElementCopyAttributeValue(child, kAXChildrenAttribute as CFString, &itemsValue)

            guard itemsResult == .success, let items = itemsValue as? [AXUIElement] else {
                continue
            }

            for item in items {
                var positionValue: AnyObject?
                var sizeValue: AnyObject?

                let posResult = AXUIElementCopyAttributeValue(item, kAXPositionAttribute as CFString, &positionValue)
                let sizeResult = AXUIElementCopyAttributeValue(item, kAXSizeAttribute as CFString, &sizeValue)

                guard posResult == .success, sizeResult == .success,
                      let posVal = positionValue, let sizeVal = sizeValue else {
                    continue
                }

                var position = CGPoint.zero
                var size = CGSize.zero

                guard AXValueGetValue(posVal as! AXValue, .cgPoint, &position),
                      AXValueGetValue(sizeVal as! AXValue, .cgSize, &size) else {
                    continue
                }

                let rect = CGRect(x: position.x, y: position.y, width: size.width, height: size.height)

                if rect.contains(clickPoint) {
                    var titleValue: AnyObject?
                    let titleResult = AXUIElementCopyAttributeValue(item, kAXTitleAttribute as CFString, &titleValue)
                    let title = (titleResult == .success) ? (titleValue as? String ?? "") : ""

                    var subroleValue: AnyObject?
                    AXUIElementCopyAttributeValue(item, kAXSubroleAttribute as CFString, &subroleValue)
                    let subrole = (subroleValue as? String) ?? ""

                    var roleDescValue: AnyObject?
                    AXUIElementCopyAttributeValue(item, kAXRoleDescriptionAttribute as CFString, &roleDescValue)
                    let roleDesc = (roleDescValue as? String) ?? ""

                    var urlValue: AnyObject?
                    AXUIElementCopyAttributeValue(item, "AXURL" as CFString, &urlValue)
                    let urlStr = urlValue as? String

                    if subrole == "AXApplicationDockItem" || roleDesc.contains("应用程序") || roleDesc.contains("application") || roleDesc.contains("приложение") || roleDesc.contains("dock") {
                        return (title, urlStr)
                    }
                    return nil
                }
            }
        }

        return nil
    }

    private func handleCloseButtonClick(at location: CGPoint) -> Bool {
        let sys = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(sys, 0.04)
        var hitElem: AXUIElement?
        guard AXUIElementCopyElementAtPosition(sys, Float(location.x), Float(location.y), &hitElem) == .success,
              let element = hitElem else {
            return false
        }

        var subroleVal: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleVal)
        guard let subrole = subroleVal as? String, subrole == (kAXCloseButtonSubrole as String) else {
            return false
        }

        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, pid != 0 else {
            return false
        }

        guard pid != ProcessInfo.processInfo.processIdentifier else { return false }

        guard let app = NSRunningApplication(processIdentifier: pid),
              app.activationPolicy == .regular else {
            return false
        }

        let excluded: Set<String> = [
            "com.apple.finder",
            "com.apple.dock",
            "com.apple.loginwindow",
            "com.apple.SystemUIServer",
            "com.apple.WindowManager",
            "com.jacktony.dockminimizer",
            "com.dockflow.app"
        ]

        if let bid = app.bundleIdentifier, excluded.contains(bid) {
            return false
        }

        LogService.shared.log(category: "CloseButton", message: "Клик по красному крестику: \(app.localizedName ?? "") (PID: \(pid))")

        // Ставим приложение на контроль закрытия
        AutoQuitter.shared.armForClose(pid: pid)

        // Проверяем количество стандартных окон
        let axApp = AXUIElementCreateApplication(pid)
        var windowsVal: AnyObject?
        _ = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsVal)
        let windows = (windowsVal as? [AXUIElement]) ?? []

        let standardWindows = windows.filter { win in
            var subVal: AnyObject?
            AXUIElementCopyAttributeValue(win, kAXSubroleAttribute as CFString, &subVal)
            let sub = (subVal as? String) ?? ""
            return sub == (kAXStandardWindowSubrole as String) || sub == ""
        }

        if standardWindows.count <= 1 {
            // Одно окно (или последнее):
            // ВАЖНО: Мы перехватываем клик (return true), чтобы окно НЕ закрывалось отдельно до завершения!
            // Браузеры (Chrome, Safari) и приложения сохраняют свои открытые вкладки/окна,
            // только если завершаются целиком с открытыми окнами (ровно так, как работает Command+Q).
            LogService.shared.log(category: "CloseButton", message: "Завершаем приложение целиком с сохранением сессии (Cmd+Q): \(app.localizedName ?? "")")
            DispatchQueue.main.async {
                app.terminate()
            }
            return true
        } else {
            // Несколько окон: даем текущему окну закрыться, и если не осталось окон — завершаем приложение
            LogService.shared.log(category: "CloseButton", message: "Осталось окон: \(standardWindows.count), закрываем окно")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                guard let checkApp = NSRunningApplication(processIdentifier: pid), !checkApp.isTerminated else { return }
                let checkAx = AXUIElementCreateApplication(pid)
                var checkWinsVal: AnyObject?
                _ = AXUIElementCopyAttributeValue(checkAx, kAXWindowsAttribute as CFString, &checkWinsVal)
                let checkWins = (checkWinsVal as? [AXUIElement]) ?? []
                let remaining = checkWins.filter { win in
                    var subVal: AnyObject?
                    AXUIElementCopyAttributeValue(win, kAXSubroleAttribute as CFString, &subVal)
                    let sub = (subVal as? String) ?? ""
                    return sub == (kAXStandardWindowSubrole as String) || sub == ""
                }
                if remaining.isEmpty {
                    LogService.shared.log(category: "CloseButton", message: "Все окна закрыты, завершаем приложение: \(checkApp.localizedName ?? "")")
                    checkApp.terminate()
                } else {
                    AutoQuitter.shared.disarmClose(pid: pid)
                }
            }
            return false
        }
    }

    func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Bool {
        guard type == .leftMouseDown else { return false }

        let location = event.location
        let mainScreenID = CGMainDisplayID()
        let displayBounds = CGDisplayBounds(mainScreenID)
        let screenHeight = displayBounds.height

        let dockHeight: CGFloat = 140

        // 1. Проверяем клик по Доку (для сворачивания / разворачивания с Джином)
        if location.y >= screenHeight - dockHeight {
            guard let appInfo = getAppInfoAtDockLocation(location) else { return false }
            guard let frontApp = NSWorkspace.shared.frontmostApplication else { return false }

            var isMatch = false
            if let urlStr = appInfo.urlString, let itemURL = URL(string: urlStr), let frontURL = frontApp.bundleURL {
                if itemURL.standardizedFileURL == frontURL.standardizedFileURL {
                    isMatch = true
                }
            }

            if !isMatch, let frontmostName = currentFrontmostName {
                let clicked = appInfo.title.lowercased()
                let front = frontmostName.lowercased()
                if clicked == front || clicked.contains(front) || front.contains(clicked) {
                    isMatch = true
                }
            }

            guard isMatch else { return false }

            LogService.shared.log(category: "DockMonitor", message: "点击 Dock 图标: \(appInfo.title)")

            let shouldConsume = WindowMinimizer.shared.toggleMinimization(app: frontApp)
            return shouldConsume
        }

        // 2. Проверяем клик по красному крестику (полное закрытие через Cmd+Q)
        let quitOnClose = UserDefaults.standard.object(forKey: "quitOnCloseButton") == nil || UserDefaults.standard.bool(forKey: "quitOnCloseButton")
        if quitOnClose {
            if handleCloseButtonClick(at: location) {
                return true
            }
        }

        return false
    }
}
