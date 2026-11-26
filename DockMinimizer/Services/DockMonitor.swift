import Cocoa
import Carbon
import UserNotifications
import os

// Global callback function for CGEventTap running on dedicated background thread
private func globalEventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo = userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let monitor = Unmanaged<DockMonitor>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if type == .tapDisabledByTimeout {
            LogService.shared.log(level: .warning, category: "DockMonitor", message: "CGEventTap disabled by timeout; re-enabling")
        }
        monitor.reenableTap()
        return Unmanaged.passUnretained(event)
    }

    let consumed = monitor.handleEvent(proxy: proxy, type: type, event: event)
    return consumed ? nil : Unmanaged.passUnretained(event)
}

/// Monitors Dock clicks, middle-clicks, and close-button clicks using an off-main-thread CGEventTap.
final class DockMonitor: ObservableObject {
    static let shared = DockMonitor()

    private struct TapState {
        var eventTap: CFMachPort?
        var runLoopSource: CFRunLoopSource?
        var tapRunLoop: CFRunLoop?
        var suppressedLeftUpUntilNs: UInt64 = 0
        var suppressedOtherUpUntilNs: UInt64 = 0
    }

    private let tapLock = OSAllocatedUnfairLock<TapState>(initialState: TapState())
    private var tapThread: Thread?
    private var permissionCheckTimer: Timer?
    private var lastPermissionState: Bool = false

    private let systemWideElement: AXUIElement = {
        let sys = AXUIElementCreateSystemWide()
        AXHelper.setTimeout(sys, AXHelper.tapTimeout)
        return sys
    }()

    @Published var isFullyFunctional: Bool = false

    private init() {
        _ = DockGeometryService.shared
        tryStartEventTap()
        startPermissionCheckTimer()
    }

    deinit {
        permissionCheckTimer?.invalidate()
        stopEventTap()
    }

    func reenableTap() {
        tapLock.withLock { state in
            if let tap = state.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }
    }

    private func startPermissionCheckTimer() {
        let trusted = AXIsProcessTrusted()
        lastPermissionState = trusted
        adjustTimerInterval()
        checkPermissionState(isInitial: true)
    }

    private func checkPermissionState(isInitial: Bool = false) {
        let trusted = AXIsProcessTrusted()
        let hasTap = tapLock.withLock { $0.eventTap != nil }

        DispatchQueue.main.async { [weak self] in
            self?.isFullyFunctional = trusted && hasTap
        }

        if trusted != lastPermissionState || isInitial {
            if !isInitial {
                LogService.shared.log(category: "DockMonitor", message: "Accessibility trust changed: \(lastPermissionState) -> \(trusted)")
                if trusted {
                    DockGeometryService.shared.rebuildObserverIfTrusted()
                    sendNotification(title: L10n.permissionGrantedNotificationTitle, body: L10n.permissionGrantedNotificationBody)
                } else {
                    sendNotification(title: L10n.permissionRevoked, body: L10n.permissionRevokedMessage)
                }
            }
            lastPermissionState = trusted
            adjustTimerInterval()
        }

        if trusted {
            if !hasTap {
                LogService.shared.log(category: "DockMonitor", message: "Accessibility permission granted, starting eventTap")
                tryStartEventTap()
            } else {
                reenableTap()
            }
        } else if hasTap {
            LogService.shared.log(level: .warning, category: "DockMonitor", message: "Accessibility permission revoked, stopping eventTap")
            stopEventTap()
        }
    }

    private func sendNotification(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            center.add(request)
        }
    }

    private func adjustTimerInterval() {
        permissionCheckTimer?.invalidate()
        let interval: TimeInterval = lastPermissionState ? 60.0 : 1.5
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.checkPermissionState()
        }
        timer.tolerance = lastPermissionState ? 15.0 : 0.5
        RunLoop.main.add(timer, forMode: .common)
        permissionCheckTimer = timer
    }

    private func stopEventTap() {
        let previous = tapLock.withLock { state -> (CFMachPort?, CFRunLoopSource?, CFRunLoop?) in
            let out = (state.eventTap, state.runLoopSource, state.tapRunLoop)
            state.eventTap = nil
            state.runLoopSource = nil
            state.tapRunLoop = nil
            state.suppressedLeftUpUntilNs = 0
            state.suppressedOtherUpUntilNs = 0
            return out
        }

        if let tap = previous.0 {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let rl = previous.2, let src = previous.1 {
            CFRunLoopPerformBlock(rl, CFRunLoopMode.commonModes.rawValue) {
                CFRunLoopRemoveSource(rl, src, .commonModes)
                CFRunLoopStop(rl)
            }
            CFRunLoopWakeUp(rl)
        }
        tapThread = nil

        DispatchQueue.main.async { [weak self] in
            self?.isFullyFunctional = false
        }
    }

    private func tryStartEventTap() {
        guard AXIsProcessTrusted() else { return }

        let alreadyRunning = tapLock.withLock { state -> Bool in
            if let tap = state.eventTap {
                if !CGEvent.tapIsEnabled(tap: tap) {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
                return true
            }
            return false
        }
        if alreadyRunning { return }

        startEventTapThread()
    }

    private func startEventTapThread() {
        let thread = Thread { [weak self] in
            guard let self else { return }

            let eventMask =
                (1 << CGEventType.leftMouseDown.rawValue) |
                (1 << CGEventType.leftMouseUp.rawValue) |
                (1 << CGEventType.otherMouseDown.rawValue) |
                (1 << CGEventType.otherMouseUp.rawValue)

            let selfPointer = Unmanaged.passUnretained(self).toOpaque()
            guard let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .tailAppendEventTap,
                options: .defaultTap,
                eventsOfInterest: CGEventMask(eventMask),
                callback: globalEventCallback,
                userInfo: selfPointer
            ) else {
                LogService.shared.log(level: .error, category: "DockMonitor", message: "Failed to create CGEventTap")
                return
            }

            let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
            let rl = CFRunLoopGetCurrent()

            self.tapLock.withLock { state in
                state.eventTap = tap
                state.runLoopSource = source
                state.tapRunLoop = rl
            }

            if let source {
                CFRunLoopAddSource(rl, source, .commonModes)
                CGEvent.tapEnable(tap: tap, enable: true)
                DispatchQueue.main.async { [weak self] in
                    self?.isFullyFunctional = AXIsProcessTrusted()
                }
                LogService.shared.log(category: "DockMonitor", message: "CGEventTap started on dedicated runloop thread")
                CFRunLoopRun()
            }
        }
        thread.name = "com.dockflow.app.eventtap"
        thread.qualityOfService = .userInteractive
        tapThread = thread
        thread.start()
    }

    // MARK: - Event Dispatch

    func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Bool {
        let now = DispatchTime.now().uptimeNanoseconds

        if type == .leftMouseUp {
            return tapLock.withLock { state in
                if state.suppressedLeftUpUntilNs != 0 && now <= state.suppressedLeftUpUntilNs {
                    state.suppressedLeftUpUntilNs = 0
                    return true
                }
                state.suppressedLeftUpUntilNs = 0
                return false
            }
        }

        if type == .otherMouseUp {
            let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
            guard buttonNumber == 2 else { return false }
            return tapLock.withLock { state in
                if state.suppressedOtherUpUntilNs != 0 && now <= state.suppressedOtherUpUntilNs {
                    state.suppressedOtherUpUntilNs = 0
                    return true
                }
                state.suppressedOtherUpUntilNs = 0
                return false
            }
        }

        if type == .otherMouseDown {
            let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
            guard buttonNumber == 2 else { return false }
            let consumed = autoreleasepool { handleMiddleClick(event: event) }
            if consumed {
                tapLock.withLock { $0.suppressedOtherUpUntilNs = now &+ 2_000_000_000 }
            }
            return consumed
        }

        guard type == .leftMouseDown else { return false }

        let consumed = autoreleasepool { handleLeftMouseDown(location: event.location) }
        if consumed {
            tapLock.withLock { $0.suppressedLeftUpUntilNs = now &+ 2_000_000_000 }
        }
        return consumed
    }

    private func handleLeftMouseDown(location: CGPoint) -> Bool {
        // 1. Dock icon click -> Genie minimize/restore if enabled and frontmost
        if let dockItem = DockGeometryService.shared.itemAt(location) {
            let genieEnabled = UserDefaults.standard.object(forKey: "genieMinimizeEnabled") == nil ||
                               UserDefaults.standard.bool(forKey: "genieMinimizeEnabled")
            if genieEnabled,
               let frontApp = NSWorkspace.shared.frontmostApplication,
               doesDockItem(dockItem, match: frontApp) {
                LogService.shared.log(category: "DockMonitor", message: "Dock click on frontmost app: \(dockItem.title)")
                return WindowMinimizer.shared.toggleMinimization(app: frontApp)
            }
            // If click landed on a non-frontmost Dock tile, let Dock handle activation normally
            return false
        }

        // 2. Red close button click (⌘Q on last window) with fast WindowServer titlebar corner pre-filter
        let quitOnClose = UserDefaults.standard.object(forKey: "quitOnCloseButton") == nil ||
                          UserDefaults.standard.bool(forKey: "quitOnCloseButton")
        guard quitOnClose, isLocationInsideEligibleTitlebarCorner(location) else {
            return false
        }

        return handleCloseButtonClick(at: location)
    }

    // MARK: - App Identity Matching (Strict URL / BundleID)

    private func doesDockItem(_ item: DockTileInfo, match app: NSRunningApplication) -> Bool {
        if let itemBID = item.bundleIdentifier, let appBID = app.bundleIdentifier {
            return itemBID == appBID
        }
        if let itemURL = item.url, let appURL = app.bundleURL {
            return itemURL.standardizedFileURL == appURL.standardizedFileURL
        }
        guard !item.title.isEmpty, let appName = app.localizedName, !appName.isEmpty else {
            return false
        }
        return item.title.caseInsensitiveCompare(appName) == .orderedSame
    }

    private func findRunningApp(for dockItem: DockTileInfo) -> NSRunningApplication? {
        let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }

        if let bid = dockItem.bundleIdentifier,
           let match = running.first(where: { $0.bundleIdentifier == bid }) {
            return match
        }
        if let itemURL = dockItem.url {
            let stdURL = itemURL.standardizedFileURL
            if let match = running.first(where: { $0.bundleURL?.standardizedFileURL == stdURL }) {
                return match
            }
        }
        guard !dockItem.title.isEmpty else { return nil }
        return running.first { app in
            guard let name = app.localizedName else { return false }
            return name.caseInsensitiveCompare(dockItem.title) == .orderedSame
        }
    }

    // MARK: - Fast In-Memory Close-Button Pre-Filter

    private func isLocationInsideEligibleTitlebarCorner(_ location: CGPoint) -> Bool {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }

        for info in windowList {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  rect.width >= 60, rect.height >= 40 else {
                continue
            }

            // Traffic lights live inside the top 48pt, within left 120pt (or right 120pt for RTL)
            let topBandMaxY = rect.minY + 48
            guard location.y >= rect.minY && location.y <= topBandMaxY else {
                continue
            }
            let inLeftCorner = location.x >= rect.minX && location.x <= rect.minX + 120
            let inRightCorner = location.x >= rect.maxX - 120 && location.x <= rect.maxX
            if inLeftCorner || inRightCorner {
                return true
            }
        }
        return false
    }

    // MARK: - Close Button Handling

    private func handleCloseButtonClick(at location: CGPoint) -> Bool {
        var hitElem: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWideElement, Float(location.x), Float(location.y), &hitElem) == .success,
              let element = hitElem else {
            return false
        }

        AXHelper.setTimeout(element, AXHelper.defaultTimeout)
        guard AXHelper.copyString(element, kAXSubroleAttribute as String) == (kAXCloseButtonSubrole as String) else {
            return false
        }

        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, pid != 0 else {
            return false
        }

        guard let app = NSRunningApplication(processIdentifier: pid),
              app.activationPolicy == .regular,
              !AppPolicy.isQuitExcluded(app: app) else {
            return false
        }

        // Validate that the close button belongs to a top-level window's own kAXCloseButtonAttribute
        guard WindowClassifier.resolveTopLevelWindow(forCloseButton: element, pid: pid) != nil else {
            return false
        }

        let classified = WindowClassifier.classifyWindows(for: pid)
        guard !classified.isEmpty else {
            return false
        }

        let appName = app.localizedName ?? (app.bundleIdentifier ?? "App")

        // Pre-close termination ONLY for explicit browser allowlist on their final top-level window
        // so open tabs/sessions are preserved cleanly.
        if AppPolicy.isSessionPreservingBrowser(bundleIdentifier: app.bundleIdentifier), classified.count == 1 {
            LogService.shared.log(category: "CloseButton", message: "Closing last window of browser \(appName) (PID: \(pid)) via ⌘Q to preserve session")
            HapticFeedbackService.shared.playTap()
            DispatchQueue.main.async {
                app.terminate()
            }
            return true
        }

        // For all non-browser apps (or browsers with 2+ windows), let macOS handle windowShouldClose
        // and Save/Cancel sheets natively, then let AutoQuitter terminate once 0 windows remain.
        LogService.shared.log(category: "CloseButton", message: "Arming AutoQuitter for \(appName) (PID: \(pid)), windows: \(classified.count)")
        AutoQuitter.shared.armForClose(pid: pid)
        return false
    }

    // MARK: - Middle-Click Handling

    private func handleMiddleClick(event: CGEvent) -> Bool {
        let actionRaw = UserDefaults.standard.string(forKey: "middleClickAction") ?? "newWindow"
        guard actionRaw != "disabled" else { return false }

        let location = event.location
        guard let dockItem = DockGeometryService.shared.itemAt(location) else {
            return false
        }

        let targetApp = findRunningApp(for: dockItem)
        LogService.shared.log(category: "MiddleClick", message: "Middle click on Dock item \(dockItem.title), action: \(actionRaw)")

        switch actionRaw {
        case "newWindow":
            if let app = targetApp {
                triggerNewWindow(for: app)
                HapticFeedbackService.shared.playTap()
                return true
            } else if let url = dockItem.url {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                    if let error {
                        LogService.shared.log(level: .error, category: "MiddleClick", message: "Failed to launch app: \(error.localizedDescription)")
                    }
                }
                HapticFeedbackService.shared.playTap()
                return true
            }
            return false

        case "quitApp":
            if let app = targetApp, !AppPolicy.isQuitExcluded(app: app) {
                HapticFeedbackService.shared.playTap()
                DispatchQueue.main.async {
                    app.terminate()
                }
                return true
            }
            return false

        case "hideApp":
            if let app = targetApp {
                HapticFeedbackService.shared.playTap()
                DispatchQueue.main.async {
                    app.hide()
                }
                return true
            }
            return false

        default:
            return false
        }
    }

    private func triggerNewWindow(for app: NSRunningApplication) {
        let pid = app.processIdentifier
        if tryPressNewWindowMenuItem(pid: pid) {
            return
        }

        DispatchQueue.main.async {
            app.activate()
        }

        // Wait up to 400ms for activation before posting layout-aware ⌘N directly to target PID
        DispatchQueue.global(qos: .userInteractive).async {
            let deadline = Date().addingTimeInterval(0.4)
            while Date() < deadline {
                if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid {
                    break
                }
                Thread.sleep(forTimeInterval: 0.02)
            }

            let keyCode = Self.virtualKeyCode(for: "n") ?? 0x2D
            guard let src = CGEventSource(stateID: .hidSystemState),
                  let keyDown = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false) else {
                return
            }
            keyDown.flags = .maskCommand
            keyUp.flags = .maskCommand
            keyDown.postToPid(pid)
            keyUp.postToPid(pid)
        }
    }

    private func tryPressNewWindowMenuItem(pid: pid_t) -> Bool {
        let axApp = AXUIElementCreateApplication(pid)
        AXHelper.setTimeout(axApp, AXHelper.defaultTimeout)
        guard let menuBar = AXHelper.copyValue(axApp, kAXMenuBarAttribute as String),
              let menuBarItems = AXHelper.copyValue(menuBar as! AXUIElement, kAXChildrenAttribute as String) as? [AXUIElement] else {
            return false
        }

        // Scan first 4 top-level menus (Apple, App, File, ...) for a direct ⌘N menu item
        for topItem in menuBarItems.prefix(4) {
            guard let menus = AXHelper.copyValue(topItem, kAXChildrenAttribute as String) as? [AXUIElement] else {
                continue
            }
            for menu in menus {
                guard let entries = AXHelper.copyValue(menu, kAXChildrenAttribute as String) as? [AXUIElement] else {
                    continue
                }
                for entry in entries {
                    let cmdChar = AXHelper.copyString(entry, kAXMenuItemCmdCharAttribute as String)
                    let cmdMod = (AXHelper.copyValue(entry, kAXMenuItemCmdModifiersAttribute as String) as? NSNumber)?.intValue ?? 0
                    if cmdChar?.uppercased() == "N" && cmdMod == 0 {
                        let enabled = AXHelper.copyBool(entry, kAXEnabledAttribute as String) ?? true
                        if enabled && AXUIElementPerformAction(entry, kAXPressAction as CFString) == .success {
                            return true
                        }
                    }
                }
            }
        }
        return false
    }

    /// Resolves virtual keycode matching ASCII character `'n'` under current keyboard layout.
    private static func virtualKeyCode(for targetChar: Character) -> CGKeyCode? {
        guard let inputSource = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let rawPtr = TISGetInputSourceProperty(inputSource, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let layoutData = unsafeBitCast(rawPtr, to: CFData.self)
        guard let bytePtr = CFDataGetBytePtr(layoutData) else { return nil }
        let keyboardLayout = UnsafePointer<UCKeyboardLayout>(OpaquePointer(bytePtr))

        let targetLower = String(targetChar).lowercased()
        for keyCode in 0..<128 {
            var deadKeyState: UInt32 = 0
            var length = 0
            var chars = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(
                keyboardLayout,
                UInt16(keyCode),
                UInt16(kUCKeyActionDown),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                chars.count,
                &length,
                &chars
            )
            if status == noErr && length > 0 {
                let produced = String(utf16CodeUnits: chars, count: length).lowercased()
                if produced == targetLower {
                    return CGKeyCode(keyCode)
                }
            }
        }
        return nil
    }
}
