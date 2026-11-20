import Cocoa

/// Автоматически завершает приложение (точь-в-точь как Command+Q),
/// ТОЛЬКО если пользователь нажал на красный крестик закрытия окна.
/// Полностью реактивный: не использует постоянных фоновых таймеров и не нагружает процессор (0% CPU в фоне).
class AutoQuitter: NSObject {
    static let shared = AutoQuitter()

    // Приложения, у которых был нажат красный крестик закрытия окна
    private var pendingClosePIDs = Set<pid_t>()
    private let lock = NSLock()

    private let excluded: Set<String> = [
        "com.apple.finder",
        "com.apple.dock",
        "com.apple.loginwindow",
        "com.apple.SystemUIServer",
        "com.apple.WindowManager",
        "com.jacktony.dockminimizer",
        "com.dockflow.app"
    ]

    private override init() {
        super.init()
    }

    /// Регистрирует, что пользователь нажал на красный крестик закрытия окна
    func armForClose(pid: pid_t) {
        lock.lock()
        pendingClosePIDs.insert(pid)
        lock.unlock()

        LogService.shared.log(category: "AutoQuitter", message: "Приложение PID \(pid) ожидает закрытия (нажат красный крестик)")

        // Точечные проверки только для данного приложения (без постоянного таймера)
        scheduleTargetedCheck(for: pid, delay: 0.35)
        scheduleTargetedCheck(for: pid, delay: 0.70)

        // Автоматически снимаем с контроля через 1.5 секунды, если приложение не завершилось
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.disarmClose(pid: pid)
        }
    }

    /// Снимает приложение с контроля закрытия
    func disarmClose(pid: pid_t) {
        lock.lock()
        pendingClosePIDs.remove(pid)
        lock.unlock()
    }

    func start() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidDeactivate(_:)),
            name: NSWorkspace.didDeactivateApplicationNotification,
            object: nil
        )

        LogService.shared.log(category: "AutoQuitter", message: "AutoQuitter запущен (реактивный режим, 0% CPU)")
    }

    func stop() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        lock.lock()
        pendingClosePIDs.removeAll()
        lock.unlock()
    }

    @objc private func appDidDeactivate(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        let pid = app.processIdentifier
        lock.lock()
        let isArmed = pendingClosePIDs.contains(pid)
        lock.unlock()

        if isArmed {
            checkSingleApp(pid: pid)
        }
    }

    private func scheduleTargetedCheck(for pid: pid_t, delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.checkSingleApp(pid: pid)
        }
    }

    private func checkSingleApp(pid: pid_t) {
        guard AXIsProcessTrusted() else { return }

        let enabled = UserDefaults.standard.object(forKey: "quitOnCloseButton") == nil ||
                      UserDefaults.standard.bool(forKey: "quitOnCloseButton")
        guard enabled else { return }

        lock.lock()
        let isArmed = pendingClosePIDs.contains(pid)
        lock.unlock()

        guard isArmed else { return }

        guard let app = NSRunningApplication(processIdentifier: pid),
              !app.isTerminated,
              app.activationPolicy == .regular,
              let bid = app.bundleIdentifier,
              !excluded.contains(bid),
              !AppExclusionManager.shared.isExcluded(bundleIdentifier: bid),
              pid != ProcessInfo.processInfo.processIdentifier else {
            disarmClose(pid: pid)
            return
        }

        // Проверяем оставшиеся стандартные окна приложения через Accessibility API
        autoreleasepool {
            let axApp = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(axApp, 0.05)
            var windowsVal: AnyObject?
            _ = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsVal)
            let windows = (windowsVal as? [AXUIElement]) ?? []

            let standardWindows = windows.filter { win in
                var subVal: AnyObject?
                AXUIElementCopyAttributeValue(win, kAXSubroleAttribute as CFString, &subVal)
                let sub = (subVal as? String) ?? ""
                return sub == (kAXStandardWindowSubrole as String) || sub == ""
            }

            if standardWindows.isEmpty {
                disarmClose(pid: pid)
                let appName = app.localizedName ?? bid
                LogService.shared.log(category: "AutoQuitter", message: "🔥 Окно закрыто крестиком, 0 окон у \(appName) (PID: \(pid)). Завершение (Command+Q)...")
                app.terminate()
            }
        }
    }
}
