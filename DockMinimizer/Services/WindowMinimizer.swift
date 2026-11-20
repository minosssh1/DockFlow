import Cocoa

/// Handles window minimization operations using Accessibility API
class WindowMinimizer {
    static let shared = WindowMinimizer()

    private init() {}

    /// Toggles minimization state of the given application
    /// If app is hidden or all windows are minimized, lets Dock restore it. Otherwise, minimizes windows with Genie animation.
    /// - Parameter app: The running application to toggle
    /// - Returns: True if event should be consumed (minimize action), false if system should handle it (activate/restore action)
    @discardableResult
    func toggleMinimization(app: NSRunningApplication) -> Bool {
        let appName = app.localizedName ?? "Unknown"
        let pid = app.processIdentifier

        // Check accessibility permission
        guard AXIsProcessTrusted() else {
            LogService.shared.log(level: .error, category: "WindowMinimizer", message: "Accessibility permission not granted")
            showPermissionNotification()
            return false
        }

        // If app is hidden, restore it
        if app.isHidden {
            AutoQuitter.shared.unregisterMinimized(pid: pid)
            let success = app.activate()
            LogService.shared.log(category: "WindowMinimizer", message: "Activate app: \(appName) (PID: \(pid)) - \(success ? "success" : "failed")")
            return false
        }

        let axApp = AXUIElementCreateApplication(pid)
        var windowsVal: AnyObject?
        let res = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsVal)

        guard res == .success, let windows = windowsVal as? [AXUIElement], !windows.isEmpty else {
            // Fallback: hide app if windows cannot be inspected
            AutoQuitter.shared.registerMinimized(pid: pid)
            app.hide()
            LogService.shared.log(category: "WindowMinimizer", message: "Hide app (no AX windows): \(appName)")
            return true
        }

        // Find visible (non-minimized) windows
        var visibleWindows: [AXUIElement] = []
        for win in windows {
            var minVal: AnyObject?
            if AXUIElementCopyAttributeValue(win, kAXMinimizedAttribute as CFString, &minVal) == .success {
                let isMin = (minVal as? Bool) ?? ((minVal as? NSNumber)?.boolValue ?? false)
                if isMin {
                    continue
                }
            }
            visibleWindows.append(win)
        }

        if visibleWindows.isEmpty {
            // All windows already minimized: let macOS Dock unminimize them with reverse Genie animation!
            AutoQuitter.shared.unregisterMinimized(pid: pid)
            LogService.shared.log(category: "WindowMinimizer", message: "All windows already minimized for \(appName), passing click to Dock")
            return false
        }

        // Защищаем приложение от автозакрытия перед сворачиванием в Док
        AutoQuitter.shared.registerMinimized(pid: pid)

        // Minimize visible windows with Genie animation
        var didMinimize = false
        for win in visibleWindows {
            var btnVal: AnyObject?
            if AXUIElementCopyAttributeValue(win, kAXMinimizeButtonAttribute as CFString, &btnVal) == .success,
               let btn = btnVal {
                if AXUIElementPerformAction(btn as! AXUIElement, kAXPressAction as CFString) == .success {
                    didMinimize = true
                    continue
                }
            }

            let setRes = AXUIElementSetAttributeValue(win, kAXMinimizedAttribute as CFString, true as CFTypeRef)
            if setRes == .success {
                didMinimize = true
            }
        }

        if !didMinimize {
            app.hide()
            LogService.shared.log(category: "WindowMinimizer", message: "Hide fallback: \(appName)")
        } else {
            LogService.shared.log(category: "WindowMinimizer", message: "Minimized with Genie: \(appName)")
        }
        return true
    }

    private func showPermissionNotification() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = L10n.permissionRequiredTitle
            alert.informativeText = L10n.permissionRequiredMessage
            alert.alertStyle = .warning
            alert.addButton(withTitle: L10n.openSystemSettings)
            alert.addButton(withTitle: L10n.later)

            if alert.runModal() == .alertFirstButtonReturn {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
}
