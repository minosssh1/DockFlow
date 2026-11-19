import Cocoa

/// Жёсткое правило: автоматически завершает приложение (точь-в-точь как Command+Q),
/// когда у него закрывается последнее видимое окно на экране.
class AutoQuitter: NSObject {
    static let shared = AutoQuitter()

    private var timer: Timer?
    // Запоминаем приложения, у которых мы видели хотя бы одно открытое окно
    private var seenWithWindows = Set<pid_t>()

    private let excluded: Set<String> = [
        "com.apple.finder",
        "com.apple.dock",
        "com.apple.loginwindow",
        "com.apple.SystemUIServer",
        "com.apple.WindowManager",
        "com.jacktony.dockminimizer"
    ]

    private override init() {
        super.init()
    }

    func start() {
        timer?.invalidate()

        // Быстрый отклик при переключении окон
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidDeactivate(_:)),
            name: NSWorkspace.didDeactivateApplicationNotification,
            object: nil
        )

        // Фоновый таймер: каждые 0.35 секунды проверяем состояние всех окон через CoreGraphics
        let t = Timer(timeInterval: 0.35, repeats: true) { [weak self] _ in
            self?.checkAllApps()
        }
        RunLoop.main.add(t, forMode: .common)
        self.timer = t

        LogService.shared.log(category: "AutoQuitter", message: "AutoQuitter (CoreGraphics жесткое правило) запущен")
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
        let enabled = UserDefaults.standard.object(forKey: "quitOnCloseButton") == nil ||
                      UserDefaults.standard.bool(forKey: "quitOnCloseButton")
        guard enabled else { return }

        // Получаем список окон через CoreGraphics (работает абсолютно для всех приложений, включая Safari)
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return
        }

        // Подсчитываем стандартные видимые окна для каждого процесса
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
                  app.isFinishedLaunching else {
                continue
            }

            let visibleCount = pidWindowCounts[pid] ?? 0

            if visibleCount > 0 {
                seenWithWindows.insert(pid)
            } else if visibleCount == 0 && seenWithWindows.contains(pid) {
                seenWithWindows.remove(pid)
                let appName = app.localizedName ?? bid
                LogService.shared.log(category: "AutoQuitter", message: "🔥 0 видимых окон у \(appName) (PID: \(pid)). Жёсткое закрытие точь-в-точь как Command+Q!")

                // 1. Штатное завершение (Command + Q)
                app.terminate()

                // 2. Если через 0.4с процесс всё ещё активен — закрываем принудительно
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    guard let checkApp = NSRunningApplication(processIdentifier: pid), !checkApp.isTerminated else { return }
                    LogService.shared.log(category: "AutoQuitter", message: "Принудительное завершение: \(appName)")
                    checkApp.forceTerminate()
                }
            }
        }

        seenWithWindows.formIntersection(currentPids)
    }
}
