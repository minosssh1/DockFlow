import Cocoa
import os

/// Handles window minimization and restoration operations using Accessibility API.
final class WindowMinimizer {
    static let shared = WindowMinimizer()

    private let lastPermissionPromptLock = OSAllocatedUnfairLock<UInt64>(initialState: 0)

    private init() {}

    /// Toggles minimization state of the given application.
    /// - Returns: `true` if the Dock click should be consumed, `false` if Dock should handle it natively.
    @discardableResult
    func toggleMinimization(app: NSRunningApplication) -> Bool {
        let appName = app.localizedName ?? "Unknown"
        let pid = app.processIdentifier

        guard AXIsProcessTrusted() else {
            LogService.shared.log(level: .error, category: "WindowMinimizer", message: "Accessibility permission not granted")
            showPermissionNotificationIfNeeded()
            return false
        }

        if app.isHidden {
            LogService.shared.log(category: "WindowMinimizer", message: "App is hidden, letting Dock restore: \(appName)")
            return false
        }

        let classified = WindowClassifier.classifyWindows(for: pid)
        guard !classified.isEmpty else {
            // Do not hide apps that have 0 user windows (e.g., Finder with only AXDesktop).
            LogService.shared.log(category: "WindowMinimizer", message: "No user windows for \(appName), passing click to Dock")
            return false
        }

        let visibleWindows = classified.filter { !$0.isMinimized }
        if visibleWindows.isEmpty {
            // All user windows are minimized: pass click to Dock for native reverse Genie restore.
            LogService.shared.log(category: "WindowMinimizer", message: "All windows already minimized for \(appName), passing click to Dock")
            return false
        }

        // Prefer windows on the active Space/Stage Manager set when available.
        let activeSpaceVisible = visibleWindows.filter { $0.isOnActiveScreenSpace }
        let candidateWindows = activeSpaceVisible.isEmpty ? visibleWindows : activeSpaceVisible

        // Skip fullscreen windows cleanly instead of calling app.hide().
        let minimizableTargets = candidateWindows.filter { !$0.isFullScreen }
        if minimizableTargets.isEmpty {
            LogService.shared.log(category: "WindowMinimizer", message: "Fullscreen window active for \(appName), passing click without hiding")
            return false
        }

        var didMinimize = false
        for winInfo in minimizableTargets {
            if let btn = AXHelper.copyValue(winInfo.element, kAXMinimizeButtonAttribute as String) {
                let btnElem = btn as! AXUIElement
                AXHelper.setTimeout(btnElem, AXHelper.defaultTimeout)
                if AXUIElementPerformAction(btnElem, kAXPressAction as CFString) == .success {
                    didMinimize = true
                    continue
                }
            }

            if AXUIElementSetAttributeValue(winInfo.element, kAXMinimizedAttribute as CFString, true as CFTypeRef) == .success {
                didMinimize = true
            }
        }

        if !didMinimize {
            let hasMinimizedAlready = classified.contains { $0.isMinimized }
            if !hasMinimizedAlready {
                DispatchQueue.main.async {
                    app.hide()
                }
                LogService.shared.log(category: "WindowMinimizer", message: "Hide fallback for non-minimizable window: \(appName)")
                HapticFeedbackService.shared.playTap()
                return true
            }
            return false
        }

        LogService.shared.log(category: "WindowMinimizer", message: "Minimized with Genie: \(appName)")
        HapticFeedbackService.shared.playTap()
        return true
    }

    private func showPermissionNotificationIfNeeded() {
        let now = DispatchTime.now().uptimeNanoseconds
        let shouldPrompt = lastPermissionPromptLock.withLock { last -> Bool in
            if last != 0 && now &- last < 30_000_000_000 { // max once every 30s
                return false
            }
            last = now
            return true
        }
        guard shouldPrompt else { return }

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
