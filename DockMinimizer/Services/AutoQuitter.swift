@preconcurrency import Cocoa
import os

private struct ArmedAppState {
    var generation: UInt64
    var observer: AXObserver?
    var axApp: AXUIElement?
}

private func autoQuitterAXCallback(
    observer: AXObserver,
    element: AXUIElement,
    notification: CFString,
    refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    let quitter = Unmanaged<AutoQuitter>.fromOpaque(refcon).takeUnretainedValue()
    var pid: pid_t = 0
    if AXUIElementGetPid(element, &pid) == .success, pid != 0 {
        quitter.handleWindowDestroyed(for: pid)
    }
}

/// Automatically quits non-excluded applications (⌘Q) after their last window finishes closing.
/// Uses AXObserver (kAXWindowDestroyedNotification) and NSWorkspace notifications with 0% idle CPU.
final class AutoQuitter: NSObject {
    static let shared = AutoQuitter()

    private let stateLock = OSAllocatedUnfairLock<[pid_t: ArmedAppState]>(initialState: [:])
    private var nextGeneration: UInt64 = 0

    private override init() {
        super.init()
    }

    func start() {
        let wsCenter = NSWorkspace.shared.notificationCenter
        wsCenter.addObserver(
            self,
            selector: #selector(appDidDeactivate(_:)),
            name: NSWorkspace.didDeactivateApplicationNotification,
            object: nil
        )
        wsCenter.addObserver(
            self,
            selector: #selector(appDidTerminate(_:)),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )
        LogService.shared.log(category: "AutoQuitter", message: "AutoQuitter started (event-driven AXObserver, 0% CPU)")
    }

    func stop() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        let states = stateLock.withLock { dict -> [ArmedAppState] in
            let all = Array(dict.values)
            dict.removeAll()
            return all
        }
        DispatchQueue.main.async {
            for state in states {
                if let observer = state.observer {
                    CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
                }
            }
        }
    }

    /// Arms target PID after a user close-button click so it terminates once its last window is gone.
    func armForClose(pid: pid_t) {
        guard AXIsProcessTrusted(),
              let app = NSRunningApplication(processIdentifier: pid),
              !app.isTerminated,
              app.activationPolicy == .regular,
              !AppPolicy.isQuitExcluded(app: app) else {
            return
        }

        let (generation, oldObserver) = stateLock.withLock { dict -> (UInt64, AXObserver?) in
            nextGeneration &+= 1
            let gen = nextGeneration
            let existing = dict[pid]?.observer
            dict[pid] = ArmedAppState(generation: gen, observer: nil, axApp: nil)
            return (gen, existing)
        }

        if let oldObserver {
            let removeOld = {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(oldObserver), .commonModes)
            }
            if Thread.isMainThread {
                removeOld()
            } else {
                DispatchQueue.main.async(execute: removeOld)
            }
        }

        LogService.shared.log(category: "AutoQuitter", message: "Armed PID \(pid) for close-to-quit")

        DispatchQueue.main.async { [weak self] in
            self?.attachWindowDestroyedObserver(for: pid, generation: generation)
        }

        // Fast targeted check for windows that close without emitting AXWindowDestroyed cleanly
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.checkSingleApp(pid: pid, expectedGeneration: generation)
        }

        // If user cancelled closing or closed 1 of N windows, disarm cleanly after 1.5s unless a modal sheet is active
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self else { return }
            let stillArmed = self.stateLock.withLock { $0[pid]?.generation == generation }
            guard stillArmed else { return }
            if !WindowClassifier.hasOpenModalOrSheet(for: pid) {
                self.checkSingleApp(pid: pid, expectedGeneration: generation)
                self.disarmClose(pid: pid, expectedGeneration: generation)
            }
        }

        // Hard safety TTL even if a Save sheet remained open indefinitely
        DispatchQueue.main.asyncAfter(deadline: .now() + 30.0) { [weak self] in
            self?.disarmClose(pid: pid, expectedGeneration: generation)
        }
    }

    func disarmClose(pid: pid_t, expectedGeneration: UInt64? = nil) {
        let removedObserver = stateLock.withLock { dict -> AXObserver? in
            guard let entry = dict[pid] else { return nil }
            if let expectedGeneration, entry.generation != expectedGeneration {
                return nil
            }
            dict.removeValue(forKey: pid)
            return entry.observer
        }
        if let observer = removedObserver {
            let removeBlock = {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            }
            if Thread.isMainThread {
                removeBlock()
            } else {
                DispatchQueue.main.async(execute: removeBlock)
            }
        }
    }

    fileprivate func handleWindowDestroyed(for pid: pid_t) {
        let gen = stateLock.withLock { $0[pid]?.generation }
        guard let gen else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.checkSingleApp(pid: pid, expectedGeneration: gen)
        }
    }

    private func attachWindowDestroyedObserver(for pid: pid_t, generation: UInt64) {
        let stillValid = stateLock.withLock { $0[pid]?.generation == generation }
        guard stillValid else { return }

        var observer: AXObserver?
        guard AXObserverCreate(pid, autoQuitterAXCallback, &observer) == .success,
              let axObserver = observer else {
            return
        }

        let axApp = AXUIElementCreateApplication(pid)
        AXHelper.setTimeout(axApp, AXHelper.defaultTimeout)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(axObserver, axApp, kAXUIElementDestroyedNotification as CFString, selfPtr)
        for win in WindowClassifier.classifyWindows(for: pid) {
            AXObserverAddNotification(axObserver, win.element, kAXUIElementDestroyedNotification as CFString, selfPtr)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(axObserver), .commonModes)

        let updated = stateLock.withLock { dict -> Bool in
            guard dict[pid]?.generation == generation else { return false }
            dict[pid]?.observer = axObserver
            dict[pid]?.axApp = axApp
            return true
        }
        if !updated {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(axObserver), .commonModes)
        }
    }

    @objc private func appDidDeactivate(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        let pid = app.processIdentifier
        if let gen = stateLock.withLock({ $0[pid]?.generation }) {
            checkSingleApp(pid: pid, expectedGeneration: gen)
        }
    }

    @objc private func appDidTerminate(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        disarmClose(pid: app.processIdentifier)
    }

    private func checkSingleApp(pid: pid_t, expectedGeneration: UInt64) {
        guard AXIsProcessTrusted() else { return }

        let enabled = UserDefaults.standard.object(forKey: "quitOnCloseButton") == nil ||
                      UserDefaults.standard.bool(forKey: "quitOnCloseButton")
        guard enabled else {
            disarmClose(pid: pid, expectedGeneration: expectedGeneration)
            return
        }

        let stillArmed = stateLock.withLock { $0[pid]?.generation == expectedGeneration }
        guard stillArmed else { return }

        guard let app = NSRunningApplication(processIdentifier: pid),
              !app.isTerminated,
              app.activationPolicy == .regular,
              !AppPolicy.isQuitExcluded(app: app) else {
            disarmClose(pid: pid, expectedGeneration: expectedGeneration)
            return
        }

        // Wait if user currently has an open Save / confirmation sheet on this app
        if WindowClassifier.hasOpenModalOrSheet(for: pid) {
            return
        }

        let remainingWindows = WindowClassifier.classifyWindows(for: pid)
        if remainingWindows.isEmpty {
            disarmClose(pid: pid, expectedGeneration: expectedGeneration)
            let appName = app.localizedName ?? (app.bundleIdentifier ?? "App")
            LogService.shared.log(category: "AutoQuitter", message: "Last window closed, terminating \(appName) (PID: \(pid))")
            HapticFeedbackService.shared.playTap()
            app.terminate()
        }
    }
}
