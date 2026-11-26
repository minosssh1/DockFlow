import Cocoa

/// Low-level Accessibility helpers with bounded IPC timeouts.
enum AXHelper {
    static let defaultTimeout: Float = 0.10
    static let tapTimeout: Float = 0.05

    static func setTimeout(_ element: AXUIElement, _ seconds: Float = defaultTimeout) {
        AXUIElementSetMessagingTimeout(element, seconds)
    }

    static func copyValue(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    static func copyString(_ element: AXUIElement, _ attribute: String) -> String? {
        copyValue(element, attribute) as? String
    }

    static func copyBool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        guard let value = copyValue(element, attribute) else { return nil }
        if let boolVal = value as? Bool { return boolVal }
        if let numVal = value as? NSNumber { return numVal.boolValue }
        return nil
    }

    static func copyURL(_ element: AXUIElement, _ attribute: String = "AXURL") -> URL? {
        guard let value = copyValue(element, attribute) else { return nil }
        if let url = value as? URL { return url }
        if let str = value as? String { return URL(string: str) }
        return nil
    }

    static func copyPoint(_ element: AXUIElement, _ attribute: String = kAXPositionAttribute as String) -> CGPoint? {
        guard let val = copyValue(element, attribute) else { return nil }
        var point = CGPoint.zero
        guard CFGetTypeID(val) == AXValueGetTypeID(),
              AXValueGetValue(val as! AXValue, .cgPoint, &point) else {
            return nil
        }
        return point
    }

    static func copySize(_ element: AXUIElement, _ attribute: String = kAXSizeAttribute as String) -> CGSize? {
        guard let val = copyValue(element, attribute) else { return nil }
        var size = CGSize.zero
        guard CFGetTypeID(val) == AXValueGetTypeID(),
              AXValueGetValue(val as! AXValue, .cgSize, &size) else {
            return nil
        }
        return size
    }

    static func copyFrame(_ element: AXUIElement) -> CGRect? {
        guard let origin = copyPoint(element), let size = copySize(element) else { return nil }
        return CGRect(origin: origin, size: size)
    }
}

/// Shared bundle identity policies for DockFlow.
enum AppPolicy {
    static let systemExcludedBundleIDs: Set<String> = [
        "com.apple.finder",
        "com.apple.dock",
        "com.apple.loginwindow",
        "com.apple.SystemUIServer",
        "com.apple.WindowManager"
    ]

    /// Browsers that require pre-close termination (⌘Q) on their last window to preserve tabs/sessions.
    static let sessionPreservingBrowserBundleIDs: Set<String> = [
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "com.google.Chrome.beta",
        "com.google.Chrome.dev",
        "org.chromium.Chromium",
        "company.thebrowser.Browser",
        "com.brave.Browser",
        "com.brave.Browser.beta",
        "com.brave.Browser.nightly",
        "com.microsoft.edgemac",
        "com.microsoft.edgemac.Beta",
        "com.microsoft.edgemac.Dev",
        "org.mozilla.firefox",
        "org.mozilla.firefoxdeveloperedition",
        "org.mozilla.nightly",
        "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera",
        "com.operasoftware.OperaGX",
        "app.zen-browser.zen",
        "com.kagi.kagimacOS"
    ]

    static func isQuitExcluded(app: NSRunningApplication) -> Bool {
        if app.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            return true
        }
        guard let bid = app.bundleIdentifier else { return false }
        if bid == Bundle.main.bundleIdentifier || bid == "com.dockflow.app" || bid == "com.jacktony.dockminimizer" {
            return true
        }
        if systemExcludedBundleIDs.contains(bid) {
            return true
        }
        return AppExclusionManager.shared.isExcluded(bundleIdentifier: bid)
    }

    static func isSessionPreservingBrowser(bundleIdentifier: String?) -> Bool {
        guard let bid = bundleIdentifier else { return false }
        return sessionPreservingBrowserBundleIDs.contains(bid)
    }
}

/// Represents a classified user window belonging to a running application.
struct ClassifiedWindow {
    let element: AXUIElement
    let subrole: String
    let frame: CGRect
    let isMinimized: Bool
    let isFullScreen: Bool
    let hasCloseButton: Bool
    let hasMinimizeButton: Bool
    let isOnActiveScreenSpace: Bool
}

/// Centralized window classifier shared across DockMonitor, WindowMinimizer, and AutoQuitter.
enum WindowClassifier {
    private static let ignoredSubroles: Set<String> = [
        "AXDesktop",
        kAXSystemDialogSubrole as String,
        kAXFloatingWindowSubrole as String,
        "AXPopover",
        "AXSheet",
        "AXUnknown"
    ]

    /// Inspects and classifies top-level user windows for the given PID.
    static func classifyWindows(for pid: pid_t) -> [ClassifiedWindow] {
        let axApp = AXUIElementCreateApplication(pid)
        AXHelper.setTimeout(axApp, AXHelper.defaultTimeout)

        guard let windows = AXHelper.copyValue(axApp, kAXWindowsAttribute as String) as? [AXUIElement],
              !windows.isEmpty else {
            return []
        }

        let onScreenFrames = activeOnScreenWindowFrames(for: pid)

        struct RawEntry {
            let element: AXUIElement
            let subrole: String
            let frame: CGRect
            let isMinimized: Bool
            let isFullScreen: Bool
            let isModal: Bool
            let hasCloseButton: Bool
            let hasMinimizeButton: Bool
        }

        var rawEntries: [RawEntry] = []
        var hasStandardWindow = false

        for win in windows {
            AXHelper.setTimeout(win, AXHelper.defaultTimeout)
            let role = AXHelper.copyString(win, kAXRoleAttribute as String) ?? ""
            if role == (kAXSheetRole as String) { continue }

            let subrole = AXHelper.copyString(win, kAXSubroleAttribute as String) ?? ""
            if ignoredSubroles.contains(subrole) { continue }

            let isModal = AXHelper.copyBool(win, kAXModalAttribute as String) ?? false
            if isModal { continue }

            let isMinimized = AXHelper.copyBool(win, kAXMinimizedAttribute as String) ?? false
            let frame = isMinimized ? .zero : (AXHelper.copyFrame(win) ?? .zero)

            if !isMinimized && (frame.width < 40 || frame.height < 40) {
                continue
            }

            let isFullScreen = isMinimized ? false : (AXHelper.copyBool(win, "AXFullScreen") ?? false)

            let isStandard = (subrole == (kAXStandardWindowSubrole as String))
            if isStandard {
                hasStandardWindow = true
            }

            let hasCloseButton: Bool
            let hasMinimizeButton: Bool
            if isStandard {
                hasCloseButton = true
                hasMinimizeButton = true
            } else {
                hasCloseButton = AXHelper.copyValue(win, kAXCloseButtonAttribute as String) != nil
                hasMinimizeButton = AXHelper.copyValue(win, kAXMinimizeButtonAttribute as String) != nil
            }

            rawEntries.append(RawEntry(
                element: win,
                subrole: subrole,
                frame: frame,
                isMinimized: isMinimized,
                isFullScreen: isFullScreen,
                isModal: isModal,
                hasCloseButton: hasCloseButton,
                hasMinimizeButton: hasMinimizeButton
            ))
        }

        var result: [ClassifiedWindow] = []
        for entry in rawEntries {
            let qualifies: Bool
            if entry.subrole == (kAXStandardWindowSubrole as String) {
                qualifies = true
            } else if entry.subrole == (kAXDialogSubrole as String) {
                // Include top-level non-modal AXDialog windows (e.g. Safari PWAs) when they are primary app windows.
                qualifies = !hasStandardWindow && (entry.hasCloseButton || entry.hasMinimizeButton)
            } else if entry.subrole.isEmpty {
                qualifies = (entry.hasCloseButton || entry.hasMinimizeButton) && (entry.isMinimized || (entry.frame.width >= 80 && entry.frame.height >= 80))
            } else {
                qualifies = false
            }

            guard qualifies else { continue }

            let isOnSpace: Bool
            if entry.isMinimized {
                isOnSpace = false
            } else if onScreenFrames.isEmpty {
                // If WindowServer reports zero layer-0 windows, window is hidden or off-Space.
                isOnSpace = false
            } else {
                isOnSpace = onScreenFrames.contains { wsRect in
                    abs(wsRect.origin.x - entry.frame.origin.x) <= 12 &&
                    abs(wsRect.origin.y - entry.frame.origin.y) <= 12 &&
                    abs(wsRect.width - entry.frame.width) <= 12 &&
                    abs(wsRect.height - entry.frame.height) <= 12
                }
            }

            result.append(ClassifiedWindow(
                element: entry.element,
                subrole: entry.subrole,
                frame: entry.frame,
                isMinimized: entry.isMinimized,
                isFullScreen: entry.isFullScreen,
                hasCloseButton: entry.hasCloseButton,
                hasMinimizeButton: entry.hasMinimizeButton,
                isOnActiveScreenSpace: isOnSpace
            ))
        }

        return result
    }

    /// Checks whether the application currently presents a modal sheet or save prompt dialog.
    static func hasOpenModalOrSheet(for pid: pid_t) -> Bool {
        let axApp = AXUIElementCreateApplication(pid)
        AXHelper.setTimeout(axApp, AXHelper.defaultTimeout)

        guard let windows = AXHelper.copyValue(axApp, kAXWindowsAttribute as String) as? [AXUIElement] else {
            return false
        }

        for win in windows {
            AXHelper.setTimeout(win, AXHelper.defaultTimeout)
            let role = AXHelper.copyString(win, kAXRoleAttribute as String) ?? ""
            let subrole = AXHelper.copyString(win, kAXSubroleAttribute as String) ?? ""
            let isModal = AXHelper.copyBool(win, kAXModalAttribute as String) ?? false
            if role == (kAXSheetRole as String) || subrole == "AXSheet" || isModal {
                return true
            }
            if let children = AXHelper.copyValue(win, kAXChildrenAttribute as String) as? [AXUIElement] {
                for child in children {
                    let childRole = AXHelper.copyString(child, kAXRoleAttribute as String) ?? ""
                    let childSubrole = AXHelper.copyString(child, kAXSubroleAttribute as String) ?? ""
                    if childRole == (kAXSheetRole as String) || childSubrole == "AXSheet" {
                        return true
                    }
                }
            }
        }
        return false
    }

    /// Validates that a hit AXCloseButton belongs to a top-level window's own kAXCloseButtonAttribute (not a tab/sheet/popover).
    static func resolveTopLevelWindow(forCloseButton hitElement: AXUIElement, pid: pid_t) -> AXUIElement? {
        AXHelper.setTimeout(hitElement, AXHelper.defaultTimeout)
        var current: AXUIElement = hitElement
        var owningWindow: AXUIElement?

        for _ in 0..<4 {
            guard let parent = AXHelper.copyValue(current, kAXParentAttribute as String) else {
                break
            }
            let parentElem = parent as! AXUIElement
            AXHelper.setTimeout(parentElem, AXHelper.defaultTimeout)
            let role = AXHelper.copyString(parentElem, kAXRoleAttribute as String) ?? ""
            if role == (kAXWindowRole as String) {
                owningWindow = parentElem
                break
            }
            if role == (kAXSheetRole as String) || role == (kAXPopoverRole as String) || role == "AXTabGroup" {
                return nil
            }
            current = parentElem
        }

        guard let window = owningWindow else { return nil }
        guard let winCloseButton = AXHelper.copyValue(window, kAXCloseButtonAttribute as String) else {
            return nil
        }

        // Reject tab close buttons or embedded controls whose AXCloseButton does not equal the hit element.
        guard CFEqual(winCloseButton, hitElement) else {
            return nil
        }

        let subrole = AXHelper.copyString(window, kAXSubroleAttribute as String) ?? ""
        if ignoredSubroles.contains(subrole) {
            return nil
        }
        if AXHelper.copyBool(window, kAXModalAttribute as String) == true {
            return nil
        }

        // Ensure AXDialog only qualifies if it's a primary window (app has no AXStandardWindow).
        if subrole == (kAXDialogSubrole as String) {
            let classified = classifyWindows(for: pid)
            let matchesClassified = classified.contains { CFEqual($0.element, window) }
            if !matchesClassified {
                return nil
            }
        }

        return window
    }

    /// Returns Quartz-coordinate rectangles of all on-screen layer-0 windows for the given PID.
    private static func activeOnScreenWindowFrames(for pid: pid_t) -> [CGRect] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        var frames: [CGRect] = []
        for info in list {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID == pid,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
                continue
            }
            if rect.width >= 40 && rect.height >= 40 {
                frames.append(rect)
            }
        }
        return frames
    }
}
