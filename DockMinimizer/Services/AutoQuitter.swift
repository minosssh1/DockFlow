import Cocoa

/// Автоматически завершает приложение (точь-в-точь как Command+Q),
/// когда у него закрывается последнее видимое окно на экране.
/// ВАЖНО: Никогда не завершает приложения, которые свёрнуты (в Док) или скрыты (Cmd+H).
class AutoQuitter: NSObject {
    static let shared = AutoQuitter()

    private var timer: Timer?
    // Запоминаем приложения, у которых мы видели хотя бы одно открытое окно на экране
    private var seenWithWindows = Set<pid_t>()
    // Запоминаем приложения, которые свёрнуты (через Док, желтую кнопку или Cmd+M)
    private var minimizedPIDs = Set<pid_t>()
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

    /// Отмечает приложение как свёрнутое (не закрывать при 0 видимых окон)
    func registerMinimized(pid: pid_t) {
        lock.lock()
        defer { lock.unlock() }
        minimizedPIDs.insert(pid)
        LogService.shared.log(category: "AutoQuitter", message: "Приложение PID \(pid) отмечено как свёрнутое (защита от закрытия)")
    }

    /// Снимает отметку свёрнутого приложения при его восстановлении
    func unregisterMinimized(pid: pid_t) {
        lock.lock()
        defer { lock.unlock() }
        if minimizedPIDs.remove(pid) != nil {
            LogService.shared.log(category: "AutoQuitter", message: "Приложение PID \(pid) развёрнуто")
        }
    }

    /// Проверяет, зарегистрировано ли приложение как свёрнутое
    func isMinimized(pid: pid_t) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return minimizedPIDs.contains(pid)
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

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        // Фоновый таймер: каждые 0.35 секунды проверяем состояние всех окон через CoreGraphics
        let t = Timer(timeInterval: 0.35, repeats: true) { [weak self] _ in
            self?.checkAllApps()
        }
        RunLoop.main.add(t, forMode: .common)
        self.timer = t

        LogService.shared.log(category: "AutoQuitter", message: "AutoQuitter запущен с защитой свёрнутых и скрытых окон")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func appDidDeactivate(_ note: Notification) {
        checkAllApps()
    }

    @objc private func appDidActivate(_ note: Notification) {
        if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
            unregisterMinimized(pid: app.processIdentifier)
        }
    }

    /// Дополнительная проверка: есть ли у приложения свёрнутые окна по Accessibility API
    private func hasMinimizedWindows(pid: pid_t) -> Bool {
        let axApp = AXUIElementCreateApplication(pid)
        var val: AnyObject?
        if AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &val) == .success,
           let wins = val as? [AXUIElement] {
            for w in wins {
                var minVal: AnyObject?
                if AXUIElementCopyAttributeValue(w, kAXMinimizedAttribute as CFString, &minVal) == .success {
                    let isMin = (minVal as? Bool) ?? ((minVal as? NSNumber)?.boolValue ?? false)
                    if isMin {
                        return true
                    }
                }
            }
        }
        return false
    }

    private func checkAllApps() {
        guard AXIsProcessTrusted() else { return }

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
                  pid != ProcessInfo.processInfo.processIdentifier,
                  app.isFinishedLaunching else {
                continue
            }

            // 1. Пропускаем скрытые приложения (Command + H)
            if app.isHidden {
                continue
            }

            // 2. Пропускаем свёрнутые приложения (через Док, желтую кнопку или Cmd+M)
            if isMinimized(pid: pid) || hasMinimizedWindows(pid: pid) {
                continue
            }

            let visibleCount = pidWindowCounts[pid] ?? 0

            if visibleCount > 0 {
                seenWithWindows.insert(pid)
                unregisterMinimized(pid: pid)
            } else if visibleCount == 0 && seenWithWindows.contains(pid) {
                seenWithWindows.remove(pid)
                let appName = app.localizedName ?? bid
                LogService.shared.log(category: "AutoQuitter", message: "🔥 0 видимых окон у \(appName) (PID: \(pid)). Завершение (Command+Q)...")

                // Штатное завершение (Command + Q) с сохранением сессий
                app.terminate()
            }
        }

        seenWithWindows.formIntersection(currentPids)
    }
}
