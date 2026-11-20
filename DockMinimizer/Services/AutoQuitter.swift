import Cocoa

/// Автоматически завершает приложение (точь-в-точь как Command+Q),
/// ТОЛЬКО если пользователь нажал на красный крестик закрытия окна.
/// Исключает случайное закрытие свёрнутых или разворачиваемых из Дока приложений.
class AutoQuitter: NSObject {
    static let shared = AutoQuitter()

    private var timer: Timer?
    // Приложения, у которых был нажат красный крестик закрытия окна
    private var pendingClosePIDs = Set<pid_t>()
    // Запоминаем приложения, у которых мы видели хотя бы одно открытое окно на экране
    private var seenWithWindows = Set<pid_t>()
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
        defer { lock.unlock() }
        pendingClosePIDs.insert(pid)
        LogService.shared.log(category: "AutoQuitter", message: "Приложение PID \(pid) ожидает закрытия (нажат красный крестик)")
    }

    /// Снимает приложение с контроля закрытия (если есть другие открытые окна)
    func disarmClose(pid: pid_t) {
        lock.lock()
        defer { lock.unlock() }
        pendingClosePIDs.remove(pid)
    }

    func start() {
        timer?.invalidate()

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidDeactivate(_:)),
            name: NSWorkspace.didDeactivateApplicationNotification,
            object: nil
        )

        // Фоновый таймер: каждые 0.35 секунды проверяем приложения в очереди закрытия
        let t = Timer(timeInterval: 0.35, repeats: true) { [weak self] _ in
            self?.checkAllApps()
        }
        RunLoop.main.add(t, forMode: .common)
        self.timer = t

        LogService.shared.log(category: "AutoQuitter", message: "AutoQuitter запущен (контроль только при нажатии на красный крестик)")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func appDidDeactivate(_ note: Notification) {
        checkAllApps()
    }

    private func checkAllApps() {
        guard AXIsProcessTrusted() else { return }

        let enabled = UserDefaults.standard.object(forKey: "quitOnCloseButton") == nil ||
                      UserDefaults.standard.bool(forKey: "quitOnCloseButton")
        guard enabled else { return }

        lock.lock()
        let pidsToWatch = pendingClosePIDs
        lock.unlock()

        // Получаем список окон через CoreGraphics
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return
        }

        var pidWindowCounts: [pid_t: Int] = [:]
        for win in windowList {
            guard let ownerPID = win[kCGWindowOwnerPID as String] as? pid_t else { continue }
            let layer = win[kCGWindowLayer as String] as? Int ?? -1
            if layer == 0 {
                let bounds = win[kCGWindowBounds as String] as? [String: Any] ?? [:]
                let w = bounds["Width"] as? CGFloat ?? 0
                let h = bounds["Height"] as? CGFloat ?? 0
                if w > 100 && h > 100 {
                    pidWindowCounts[ownerPID, default: 0] += 1
                }
            }
        }

        let runningApps = NSWorkspace.shared.runningApplications
        var currentPids = Set<pid_t>()

        for app in runningApps {
            let pid = app.processIdentifier
            currentPids.insert(pid)

            guard app.activationPolicy == .regular,
                  let bid = app.bundleIdentifier,
                  !excluded.contains(bid),
                  pid != ProcessInfo.processInfo.processIdentifier,
                  app.isFinishedLaunching else {
                continue
            }

            let visibleCount = pidWindowCounts[pid] ?? 0

            if visibleCount > 0 {
                seenWithWindows.insert(pid)
            } else if visibleCount == 0 && seenWithWindows.contains(pid) {
                // ВАЖНО: Завершаем ТОЛЬКО если пользователь нажимал красный крестик для этого приложения!
                if pidsToWatch.contains(pid) {
                    seenWithWindows.remove(pid)
                    disarmClose(pid: pid)

                    let appName = app.localizedName ?? bid
                    LogService.shared.log(category: "AutoQuitter", message: "🔥 Окно закрыто крестиком, 0 видимых окон у \(appName) (PID: \(pid)). Завершение (Command+Q)...")

                    app.terminate()
                }
            }
        }

        seenWithWindows.formIntersection(currentPids)
    }
}
