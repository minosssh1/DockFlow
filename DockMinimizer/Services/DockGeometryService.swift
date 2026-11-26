import Cocoa
import os

/// Cached Dock tile representation in global Quartz display coordinates.
struct DockTileInfo {
    let rect: CGRect
    let title: String
    let url: URL?
    let bundleIdentifier: String?
    let isRunning: Bool
}

private struct DockGeometrySnapshot {
    var dockBounds: CGRect = .zero
    var items: [DockTileInfo] = []
    var displayBounds: [CGRect] = []
}

private func dockObserverCallback(
    observer: AXObserver,
    element: AXUIElement,
    notification: CFString,
    refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    let service = Unmanaged<DockGeometryService>.fromOpaque(refcon).takeUnretainedValue()
    service.scheduleRefresh()
}

/// Maintains an asynchronous, lock-guarded cache of Dock item rectangles and screen bounds in Quartz coordinates.
final class DockGeometryService {
    static let shared = DockGeometryService()

    private let stateLock = OSAllocatedUnfairLock<DockGeometrySnapshot>(initialState: DockGeometrySnapshot())
    private let refreshQueue = DispatchQueue(label: "com.dockflow.app.dockgeometry", qos: .userInteractive)

    private var dockObserver: AXObserver?
    private var observedDockPID: pid_t = 0
    private var lastSyncRefreshNs: UInt64 = 0

    private init() {
        refreshDisplayBounds()
        startObservers()
        scheduleRefresh()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        detachObserver()
    }

    // MARK: - Public Lookup (Zero-IPC Fast Path)

    /// Returns the Dock application tile under `clickPoint` (Quartz top-left global coordinates).
    /// Performs zero IPC for clicks outside Dock edges; performs at most one bounded 25ms refresh
    /// if the click lands inside a Dock screen edge and cache missed (e.g., auto-hide reveal or magnification).
    func itemAt(_ clickPoint: CGPoint) -> DockTileInfo? {
        let snapshot = stateLock.withLock { $0 }

        if let hit = snapshot.items.first(where: { $0.rect.contains(clickPoint) }) {
            return hit
        }

        // Only query Dock synchronously if the click is actually inside the Dock area or near a Dock edge.
        let expandedDock = snapshot.dockBounds.isEmpty ? .zero : snapshot.dockBounds.insetBy(dx: -36, dy: -36)
        let nearEdge = isNearAnyDisplayEdge(clickPoint, displayBounds: snapshot.displayBounds)
        guard expandedDock.contains(clickPoint) || nearEdge else {
            return nil
        }

        let now = DispatchTime.now().uptimeNanoseconds
        let shouldThrottle = stateLock.withLock { _ -> Bool in
            if now &- lastSyncRefreshNs < 50_000_000 { // 50ms debounce
                return true
            }
            lastSyncRefreshNs = now
            return false
        }
        guard !shouldThrottle else { return nil }

        let updated = performRefreshSync()
        return updated.items.first(where: { $0.rect.contains(clickPoint) })
    }

    func scheduleRefresh() {
        refreshQueue.async { [weak self] in
            _ = self?.performRefreshSync()
        }
    }

    func rebuildObserverIfTrusted() {
        refreshQueue.async { [weak self] in
            self?.attachObserverIfNeeded()
            _ = self?.performRefreshSync()
        }
    }

    // MARK: - Observers

    private func startObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        let wsCenter = NSWorkspace.shared.notificationCenter
        wsCenter.addObserver(
            self,
            selector: #selector(workspaceAppsChanged(_:)),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )
        wsCenter.addObserver(
            self,
            selector: #selector(workspaceAppsChanged(_:)),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )

        refreshQueue.async { [weak self] in
            self?.attachObserverIfNeeded()
        }
    }

    @objc private func screenParametersChanged() {
        refreshDisplayBounds()
        scheduleRefresh()
    }

    @objc private func workspaceAppsChanged(_ notification: Notification) {
        if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
           app.bundleIdentifier == "com.apple.dock" {
            refreshQueue.async { [weak self] in
                self?.detachObserver()
                self?.attachObserverIfNeeded()
                _ = self?.performRefreshSync()
            }
        } else {
            scheduleRefresh()
        }
    }

    private func attachObserverIfNeeded() {
        guard AXIsProcessTrusted(),
              let dockApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            return
        }

        let pid = dockApp.processIdentifier
        if dockObserver != nil && observedDockPID == pid {
            return
        }

        detachObserver()

        var observer: AXObserver?
        guard AXObserverCreate(pid, dockObserverCallback, &observer) == .success,
              let axObserver = observer else {
            return
        }

        let dockRef = AXUIElementCreateApplication(pid)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let notifications: [String] = [
            kAXLayoutChangedNotification as String,
            kAXMovedNotification as String,
            kAXResizedNotification as String,
            kAXCreatedNotification as String,
            kAXUIElementDestroyedNotification as String
        ]

        for notif in notifications {
            AXObserverAddNotification(axObserver, dockRef, notif as CFString, selfPtr)
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(axObserver), .commonModes)
        dockObserver = axObserver
        observedDockPID = pid
    }

    private func detachObserver() {
        if let observer = dockObserver {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            dockObserver = nil
        }
        observedDockPID = 0
    }

    // MARK: - Refresh Logic

    private func refreshDisplayBounds() {
        let displays = Self.activeDisplayBounds()
        stateLock.withLock { $0.displayBounds = displays }
    }

    private func performRefreshSync() -> DockGeometrySnapshot {
        let displays = Self.activeDisplayBounds()
        guard AXIsProcessTrusted(),
              let dockApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            let empty = DockGeometrySnapshot(dockBounds: .zero, items: [], displayBounds: displays)
            stateLock.withLock { $0 = empty }
            return empty
        }

        let dockRef = AXUIElementCreateApplication(dockApp.processIdentifier)
        AXHelper.setTimeout(dockRef, 0.03)

        guard let children = AXHelper.copyValue(dockRef, kAXChildrenAttribute as String) as? [AXUIElement] else {
            let snap = DockGeometrySnapshot(dockBounds: .zero, items: [], displayBounds: displays)
            stateLock.withLock { $0 = snap }
            return snap
        }

        var dockBounds = CGRect.zero
        var parsedItems: [DockTileInfo] = []

        for child in children {
            AXHelper.setTimeout(child, 0.025)
            guard AXHelper.copyString(child, kAXRoleAttribute as String) == (kAXListRole as String) else {
                continue
            }

            if let listFrame = AXHelper.copyFrame(child) {
                dockBounds = dockBounds.isEmpty ? listFrame : dockBounds.union(listFrame)
            }

            guard let items = AXHelper.copyValue(child, kAXChildrenAttribute as String) as? [AXUIElement] else {
                continue
            }

            for item in items {
                AXHelper.setTimeout(item, 0.02)
                guard let subrole = AXHelper.copyString(item, kAXSubroleAttribute as String),
                      subrole == "AXApplicationDockItem" else {
                    continue
                }

                guard let rect = AXHelper.copyFrame(item), rect.width > 0, rect.height > 0 else {
                    continue
                }

                let title = AXHelper.copyString(item, kAXTitleAttribute as String) ?? ""
                let url = AXHelper.copyURL(item, "AXURL")
                let bundleID = url.flatMap { Bundle(url: $0)?.bundleIdentifier }
                let isRunning = AXHelper.copyBool(item, "AXIsApplicationRunning") ?? false

                parsedItems.append(DockTileInfo(
                    rect: rect,
                    title: title,
                    url: url,
                    bundleIdentifier: bundleID,
                    isRunning: isRunning
                ))
            }
        }

        let snapshot = DockGeometrySnapshot(dockBounds: dockBounds, items: parsedItems, displayBounds: displays)
        stateLock.withLock { $0 = snapshot }
        return snapshot
    }

    private static func activeDisplayBounds() -> [CGRect] {
        var displayCount: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &displayCount) == .success, displayCount > 0 else {
            return [CGDisplayBounds(CGMainDisplayID())]
        }
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        guard CGGetActiveDisplayList(displayCount, &displayIDs, &displayCount) == .success else {
            return [CGDisplayBounds(CGMainDisplayID())]
        }
        return displayIDs.prefix(Int(displayCount)).map { CGDisplayBounds($0) }
    }

    private func isNearAnyDisplayEdge(_ point: CGPoint, displayBounds: [CGRect]) -> Bool {
        let edgeThreshold: CGFloat = 150
        for bounds in displayBounds {
            guard bounds.contains(point) else { continue }
            if point.y >= bounds.maxY - edgeThreshold ||
               point.x <= bounds.minX + edgeThreshold ||
               point.x >= bounds.maxX - edgeThreshold {
                return true
            }
        }
        return false
    }
}
