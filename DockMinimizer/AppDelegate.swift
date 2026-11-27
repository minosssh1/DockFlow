import Cocoa
import SwiftUI
import Combine
import UserNotifications

/// Migrates user preferences once from legacy `com.jacktony.dockminimizer` suite to `com.dockflow.app`.
private enum LegacyDefaultsMigrator {
    private static let legacySuite = "com.jacktony.dockminimizer"
    private static let markerKey = "migratedFromLegacyBundle_v1"

    static func migrateIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: markerKey) else { return }
        defer { defaults.set(true, forKey: markerKey) }

        guard let oldDefaults = UserDefaults(suiteName: legacySuite) else { return }
        let keysToMigrate = [
            "appLanguage",
            "loggingEnabled",
            "showPanelOnLaunch",
            "quitOnCloseButton",
            "hapticFeedbackEnabled",
            "middleClickAction",
            "quitOnCloseExcludedBundleIDs",
            "updateCheckPolicy",
            "lastUpdateCheckTime"
        ]

        for key in keysToMigrate {
            if defaults.object(forKey: key) == nil, let oldValue = oldDefaults.object(forKey: key) {
                defaults.set(oldValue, forKey: key)
            }
        }
    }
}

/// Borderless floating panel anchored below the Menu Bar icon, enabling custom M3 Silk Materialize motion.
private final class FloatingMenuPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, UNUserNotificationCenterDelegate {
    var statusItem: NSStatusItem?
    var dockMonitor: DockMonitor?
    private var permissionAlertShown = false
    private var floatingPanel: FloatingMenuPanel?
    private var panelHostingView: NSHostingView<SettingsView>?
    private let panelFixedCanvasHeight: CGFloat = 540
    private var cachedTabHeights: [PopoverTab: CGFloat] = [:]
    private let panelUIState = PopoverUIState(initialTab: .rules, isPanelPresented: false)
    private var isPanelOpen = false
    private var panelCloseTask: Task<Void, Never>?
    private var globalClickMonitor: Any?
    private var localKeyMonitor: Any?
    private var isModalSuspended = false
    private var updateWindow: NSWindow?
    private var updateDownloader: UpdateDownloader?
    private var cancellables = Set<AnyCancellable>()
    private var updateService = UpdateService.shared

    override init() {
        LegacyDefaultsMigrator.migrateIfNeeded()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Reload preferences in case singletons initialized prior to AppDelegate.init()
        LocalizationManager.shared.reloadPreference()
        LogService.shared.reloadPreference()
        HapticFeedbackService.shared.reloadPreference()
        AppExclusionManager.shared.reloadPreference()
        UpdateService.shared.reloadPreference()

        #if DEBUG
        if CommandLine.arguments.contains("--render-screenshots") {
            renderScreenshotsAndExit()
            return
        }
        #endif

        LogService.shared.log(category: "AppDelegate", message: "App launched: \(Bundle.main.bundlePath)")

        NSApplication.shared.setActivationPolicy(.accessory)
        UNUserNotificationCenter.current().delegate = self

        createStatusItem()
        setupPopover()

        LocalizationManager.shared.$currentLanguage
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updateStatusItemAppearance()
                }
            }
            .store(in: &cancellables)

        checkAccessibilityPermission()

        dockMonitor = DockMonitor.shared
        AutoQuitter.shared.start()

        let hasKey = UserDefaults.standard.object(forKey: "showPanelOnLaunch") != nil
        let showPanelOnLaunch = hasKey ? UserDefaults.standard.bool(forKey: "showPanelOnLaunch") : false
        if showPanelOnLaunch {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.openPopover()
            }
        }

        // Passive startup update check: never steals user focus with a modal dialog
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await updateService.checkForUpdates()
            if updateService.updateAvailable {
                await MainActor.run {
                    self.sendUpdateAvailableNotification()
                }
            }
        }

        updateService.$updateAvailable
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updateStatusItemAppearance()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)
            .sink { [weak self] _ in
                guard let self, !self.isModalSuspended, !self.isPointerOverStatusItemButton() else { return }
                self.closePopover()
            }
            .store(in: &cancellables)
    }

    private func checkAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let hasPermission = AXIsProcessTrustedWithOptions(options)

        if !hasPermission {
            showPermissionAlert()
        }
    }

    private func showPermissionAlert() {
        guard !permissionAlertShown else { return }
        permissionAlertShown = true

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

    private func sendUpdateAvailableNotification() {
        let latest = updateService.latestVersion ?? ""
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "\(L10n.updateAlertTitle) (\(latest))"
            content.body = L10n.updateNotificationBody
            content.sound = .default
            content.userInfo = ["action": "openUpdateAlert"]
            let request = UNNotificationRequest(identifier: "dockflow-update-\(latest)", content: content, trigger: nil)
            center.add(request)
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.notification.request.content.userInfo["action"] as? String == "openUpdateAlert" {
            DispatchQueue.main.async { [weak self] in
                self?.showUpdateAvailableAlert()
            }
        }
        completionHandler()
    }

    private func createStatusItem() {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let item = self.statusItem, let button = item.button else { return }

        updateStatusItemAppearance()
        button.target = self
        button.action = #selector(handleStatusBarClick)
        button.sendAction(on: [.leftMouseDown, .rightMouseUp])

        item.isVisible = true
        button.isHidden = false
    }

    private func setupPopover() {
        let rootView = SettingsView(
            initialTab: .rules,
            uiState: panelUIState,
            fixedCanvasHeight: panelFixedCanvasHeight,
            onSelectTab: { [weak self] tab in
                self?.switchPanelTab(tab)
            },
            onContentChanged: { [weak self] in
                self?.refreshCurrentTabHeight(animated: true)
            },
            onPickExcludedApp: { [weak self] in
                self?.pickExcludedAppSafely()
            },
            onCheckForUpdates: { [weak self] in
                self?.checkUpdatesInline()
            },
            onInstallUpdate: { [weak self] in
                self?.closePopover()
                self?.performAutoUpdate()
            },
            onOpenLogs: { [weak self] in
                self?.closePopover()
                self?.openLogFolder()
            },
            onOpenAccessibilitySettings: { [weak self] in
                self?.closePopover()
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            },
            onQuit: { [weak self] in
                self?.quitApp()
            }
        )

        let hosting = NSHostingView(rootView: rootView)
        hosting.safeAreaRegions = []
        hosting.translatesAutoresizingMaskIntoConstraints = true
        // Keep hostingView pinned to the top edge with fixed 540pt height so NSWindow resize never triggers mid-animation SwiftUI relayout jumps.
        hosting.autoresizingMask = [.width, .minYMargin]
        self.panelHostingView = hosting

        let initialHeight = measureNaturalHeight(for: .rules)
        panelUIState.targetTotalHeight = initialHeight
        for tab in PopoverTab.allCases {
            _ = measureNaturalHeight(for: tab)
        }

        let panel = FloatingMenuPanel(
            contentRect: NSRect(x: 0, y: 0, width: 446, height: initialHeight),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "DockFlow"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.setAccessibilitySubrole(.dialog)

        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: panel.frame.size))
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.autoresizingMask = [.width, .height]
        hosting.frame = NSRect(x: 0, y: effect.bounds.height - panelFixedCanvasHeight, width: 446, height: panelFixedCanvasHeight)
        effect.addSubview(hosting)
        panel.contentView = effect

        self.floatingPanel = panel
    }

    private func updateStatusItemAppearance() {
        guard let button = statusItem?.button else { return }
        let symbolName = updateService.updateAvailable ? "dock.arrow.down.rectangle" : "dock.rectangle"
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "DockFlow") {
            let configured = image.withSymbolConfiguration(.init(pointSize: 13.5, weight: .medium)) ?? image
            configured.isTemplate = true
            button.image = configured
            button.title = ""
        } else {
            button.title = "DF"
        }
        button.toolTip = updateService.updateAvailable
            ? "DockFlow (\(L10n.updateAvailable))"
            : "DockFlow"
    }

    @objc private func handleStatusBarClick() {
        guard let event = NSApp.currentEvent else {
            togglePopover()
            return
        }

        if event.type == .rightMouseUp {
            closePopover()
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func showContextMenu() {
        guard let item = statusItem, let button = item.button else { return }
        let menu = NSMenu()

        let settingsItem = NSMenuItem(title: L10n.settings, action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitOnCloseKey = "quitOnCloseButton"
        let isQuitOnClose = UserDefaults.standard.object(forKey: quitOnCloseKey) == nil || UserDefaults.standard.bool(forKey: quitOnCloseKey)
        let quitOnCloseItem = NSMenuItem(title: L10n.quitOnCloseMenu, action: #selector(toggleQuitOnClose), keyEquivalent: "")
        quitOnCloseItem.target = self
        quitOnCloseItem.state = isQuitOnClose ? .on : .off
        menu.addItem(quitOnCloseItem)

        let permissionItem = NSMenuItem(title: L10n.checkPermissions, action: #selector(checkPermissionStatus), keyEquivalent: "")
        permissionItem.target = self
        menu.addItem(permissionItem)

        let logItem = NSMenuItem(title: L10n.viewLogs, action: #selector(openLogFolder), keyEquivalent: "")
        logItem.target = self
        menu.addItem(logItem)

        menu.addItem(NSMenuItem.separator())

        let updateTitle = updateService.updateAvailable
            ? "\(L10n.checkForUpdates) (\(L10n.updateAvailable))"
            : L10n.checkForUpdates
        let updateItem = NSMenuItem(title: updateTitle, action: #selector(checkForUpdates), keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: L10n.quit, action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        button.performClick(nil)
        item.menu = nil
    }

    private func togglePopover() {
        if isPanelOpen {
            closePopover()
        } else {
            openPopover()
        }
    }

    private func targetPanelFrame(for height: CGFloat, verticalOffset: CGFloat = 0) -> NSRect {
        let panelWidth: CGFloat = 446
        let clampedHeight = max(260, height)

        guard let buttonWindow = statusItem?.button?.window else {
            let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            return NSRect(
                x: screenFrame.midX - panelWidth / 2.0,
                y: screenFrame.maxY - clampedHeight - 36 + verticalOffset,
                width: panelWidth,
                height: clampedHeight
            )
        }

        let buttonFrame = buttonWindow.frame
        let targetScreen = buttonWindow.screen ?? NSScreen.main
        var originX = buttonFrame.midX - panelWidth / 2.0
        if let visible = targetScreen?.visibleFrame {
            originX = min(max(originX, visible.minX + 10.0), visible.maxX - panelWidth - 10.0)
        }
        let topAnchorY = round(buttonFrame.minY - 6.0)
        let originY = topAnchorY - clampedHeight + verticalOffset
        return NSRect(x: originX, y: originY, width: panelWidth, height: clampedHeight)
    }

    private func measureNaturalHeight(for tab: PopoverTab) -> CGFloat {
        if let cached = cachedTabHeights[tab] {
            return cached
        }
        let measurer = NSHostingView(rootView: SettingsView(initialTab: tab, fixedCanvasHeight: nil))
        measurer.safeAreaRegions = []
        measurer.layoutSubtreeIfNeeded()
        let height = ceil(max(260, measurer.fittingSize.height))
        cachedTabHeights[tab] = height
        return height
    }

    private func switchPanelTab(_ tab: PopoverTab) {
        guard panelUIState.selectedTab != tab else { return }
        let nextHeight = measureNaturalHeight(for: tab)
        let duration: TimeInterval = 0.34

        withAnimation(.timingCurve(0.22, 1.0, 0.36, 1.0, duration: duration)) {
            panelUIState.selectedTab = tab
            panelUIState.targetTotalHeight = nextHeight
        }
        resizeFloatingPanel(to: nextHeight, animated: true, duration: duration)
    }

    private func refreshCurrentTabHeight(animated: Bool) {
        cachedTabHeights.removeAll()
        let nextHeight = measureNaturalHeight(for: panelUIState.selectedTab)
        if animated {
            withAnimation(.timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.32)) {
                panelUIState.targetTotalHeight = nextHeight
            }
        } else {
            panelUIState.targetTotalHeight = nextHeight
        }
        resizeFloatingPanel(to: nextHeight, animated: animated, duration: 0.32)
    }

    private func resizeFloatingPanel(to height: CGFloat, animated: Bool, duration: TimeInterval = 0.34) {
        guard let panel = floatingPanel, isPanelOpen else { return }
        let targetFrame = targetPanelFrame(for: height)
        guard abs(panel.frame.height - targetFrame.height) > 0.5 else { return }

        if animated {
            Task { @MainActor [weak self] in
                guard let self, let panel = self.floatingPanel else { return }
                await NSAnimationContext.runAnimationGroup { context in
                    context.duration = duration
                    context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
                    panel.animator().setFrame(targetFrame, display: false)
                }
                panel.invalidateShadow()
            }
        } else {
            panel.setFrame(targetFrame, display: false)
            panel.invalidateShadow()
        }
    }

    private func openPopover() {
        guard let panel = floatingPanel, !isPanelOpen else { return }
        panelCloseTask?.cancel()
        panelCloseTask = nil
        isPanelOpen = true

        LaunchAtLoginManager.shared.refreshStatus()
        let targetHeight = measureNaturalHeight(for: panelUIState.selectedTab)
        panelUIState.targetTotalHeight = targetHeight
        let finalFrame = targetPanelFrame(for: targetHeight, verticalOffset: 0)
        let startFrame = targetPanelFrame(for: targetHeight, verticalOffset: 7)

        if !panel.isVisible {
            panelUIState.isPanelPresented = false
            panel.alphaValue = 0.0
            panel.setFrame(startFrame, display: false)
        }

        NSApplication.shared.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        installEventMonitors()

        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, self.isPanelOpen, let panel = self.floatingPanel else { return }
            withAnimation(.timingCurve(0.16, 1.0, 0.3, 1.0, duration: 0.26)) {
                self.panelUIState.isPanelPresented = true
            }
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.26
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
                panel.animator().alphaValue = 1.0
                panel.animator().setFrame(finalFrame, display: true)
            }
            guard self.isPanelOpen else { return }
            panel.invalidateShadow()
        }
    }

    private func closePopover() {
        guard isPanelOpen else { return }
        isPanelOpen = false
        removeEventMonitors()

        if let panel = floatingPanel {
            let exitFrame = targetPanelFrame(for: panel.frame.height, verticalOffset: 6)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.19
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
                panel.animator().alphaValue = 0.0
                panel.animator().setFrame(exitFrame, display: true)
            }
        }

        withAnimation(.timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.19)) {
            panelUIState.isPanelPresented = false
        }

        panelCloseTask?.cancel()
        panelCloseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard let self, !Task.isCancelled, !self.isPanelOpen else { return }
            self.floatingPanel?.orderOut(nil)
        }
    }

    private func isPointerOverStatusItemButton() -> Bool {
        guard let button = statusItem?.button, let buttonWindow = button.window else { return false }
        return buttonWindow.frame.contains(NSEvent.mouseLocation)
    }

    private func installEventMonitors() {
        removeEventMonitors()

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, !self.isModalSuspended, !self.isPointerOverStatusItemButton() else { return }
            self.closePopover()
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53, let self, self.isPanelOpen, !self.isModalSuspended {
                self.closePopover()
                return nil
            }
            return event
        }
    }

    private func removeEventMonitors() {
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
    }

    private func pickExcludedAppSafely() {
        isModalSuspended = true
        AppExclusionManager.shared.addAppViaFilePicker()
        isModalSuspended = false
        NSApplication.shared.activate(ignoringOtherApps: true)
        floatingPanel?.makeKeyAndOrderFront(nil)
    }

    private func checkUpdatesInline() {
        Task {
            await updateService.checkForUpdates(force: true)
            await MainActor.run {
                self.updateStatusItemAppearance()
            }
        }
    }

    @objc private func toggleQuitOnClose() {
        let key = "quitOnCloseButton"
        let current = UserDefaults.standard.object(forKey: key) == nil || UserDefaults.standard.bool(forKey: key)
        UserDefaults.standard.set(!current, forKey: key)
    }

    @objc private func checkPermissionStatus() {
        if AXIsProcessTrusted() {
            let alert = NSAlert()
            alert.messageText = L10n.permissionGrantedTitle
            alert.informativeText = L10n.permissionGrantedMessage
            alert.alertStyle = .informational
            alert.addButton(withTitle: L10n.ok)
            alert.runModal()
        } else {
            permissionAlertShown = false
            showPermissionAlert()
        }
    }

    @objc private func openLogFolder() {
        LogService.shared.openLogFolder()
    }

    private func showUpdateAvailableAlert() {
        LogService.shared.log(category: "UpdateService", message: "Showing update dialog: \(updateService.latestVersion ?? "?")")
        NSApplication.shared.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L10n.updateAlertTitle
        alert.informativeText = L10n.updateAlertMessage(
            current: updateService.currentVersion,
            latest: updateService.latestVersion ?? "?"
        )
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.updateNow)
        alert.addButton(withTitle: L10n.later)

        if alert.runModal() == .alertFirstButtonReturn {
            performAutoUpdate()
        }
    }

    private func performAutoUpdate() {
        guard let downloadURL = updateService.downloadURL else {
            updateService.openReleasePage()
            return
        }

        if let existingWin = updateWindow {
            NSApplication.shared.activate(ignoringOtherApps: true)
            existingWin.makeKeyAndOrderFront(nil)
            return
        }

        let targetVersion = updateService.latestVersion ?? ""
        let viewModel = UpdateProgressViewModel()
        let hostingView = NSHostingView(rootView: UpdateProgressView(viewModel: viewModel, targetVersion: targetVersion))

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 180),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = L10n.updateWindowTitle
        window.contentView = hostingView
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.updateWindow = window

        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        let downloader = UpdateDownloader()
        self.updateDownloader = downloader

        viewModel.onCancel = { [weak self, weak window] in
            downloader.cancel()
            window?.close()
            self?.updateWindow = nil
            self?.updateDownloader = nil
        }

        viewModel.onManualDownload = { [weak self, weak window] in
            downloader.cancel()
            window?.close()
            self?.updateWindow = nil
            self?.updateDownloader = nil
            self?.updateService.openReleasePage()
        }

        viewModel.stageTitle = L10n.updateStageConnecting
        viewModel.stageDetail = L10n.updateStageSecureConnection
        viewModel.isIndeterminate = true

        downloader.onProgress = { progress, written, total in
            viewModel.isIndeterminate = false
            viewModel.progress = progress
            viewModel.stageTitle = L10n.updateStageDownloading

            let mbWritten = Double(written) / (1024 * 1024)
            let mbTotal = Double(total) / (1024 * 1024)
            if total > 0 {
                viewModel.stageDetail = L10n.updateDownloadProgress(
                    writtenMB: mbWritten,
                    totalMB: mbTotal,
                    percent: Int(progress * 100)
                )
            } else {
                viewModel.stageDetail = L10n.updateDownloadProgressUnknown(writtenMB: mbWritten)
            }
        }

        downloader.onComplete = { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let stagedDMG):
                viewModel.stageTitle = L10n.updateStageVerifying
                viewModel.stageDetail = L10n.updateStageInstallingDetail
                viewModel.progress = 1.0
                viewModel.isIndeterminate = true

                Task { [weak self] in
                    guard let self else { return }
                    do {
                        try await self.updateService.verifyDMGChecksum(
                            dmgURL: stagedDMG,
                            sha256URL: self.updateService.sha256URL
                        )
                        await MainActor.run {
                            viewModel.stageTitle = L10n.updateStageRestarting
                            viewModel.stageDetail = L10n.updateStageRestartingDetail
                            Task { @MainActor [weak self] in
                                try? await Task.sleep(nanoseconds: 400_000_000)
                                guard let self else { return }
                                downloader.releaseStagingDirectoryForInstall()
                                do {
                                    try self.updateService.applyUpdateAndRestart(dmgPath: stagedDMG.path)
                                    self.updateWindow?.close()
                                    self.updateWindow = nil
                                    self.updateDownloader = nil
                                } catch {
                                    try? FileManager.default.removeItem(at: stagedDMG.deletingLastPathComponent())
                                    viewModel.isFailed = true
                                    viewModel.stageTitle = L10n.updateStageFailed
                                    viewModel.stageDetail = error.localizedDescription
                                }
                            }
                        }
                    } catch {
                        try? FileManager.default.removeItem(at: stagedDMG.deletingLastPathComponent())
                        await MainActor.run {
                            viewModel.isFailed = true
                            viewModel.stageTitle = L10n.updateStageFailed
                            viewModel.stageDetail = error.localizedDescription
                        }
                    }
                }

            case .failure(let error):
                viewModel.isFailed = true
                viewModel.stageTitle = L10n.updateStageFailed
                viewModel.stageDetail = error.localizedDescription
            }
        }

        viewModel.onRetry = {
            viewModel.isFailed = false
            viewModel.stageTitle = L10n.updateStageReconnecting
            viewModel.stageDetail = L10n.updateStageRetryingDetail
            viewModel.isIndeterminate = true
            downloader.start(url: downloadURL)
        }

        downloader.start(url: downloadURL)
    }

    @objc private func checkForUpdates() {
        Task {
            await updateService.checkForUpdates(force: true)

            await MainActor.run {
                if updateService.updateAvailable {
                    self.showUpdateAvailableAlert()
                } else if let error = updateService.errorMessage {
                    let alert = NSAlert()
                    alert.messageText = L10n.updateError
                    alert.informativeText = error
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: L10n.ok)
                    alert.runModal()
                } else {
                    let alert = NSAlert()
                    alert.messageText = L10n.alreadyUpToDate
                    alert.informativeText = "\(L10n.currentVersion): \(updateService.currentVersion)"
                    alert.alertStyle = .informational
                    alert.addButton(withTitle: L10n.ok)
                    alert.runModal()
                }
            }
        }
    }

    @objc private func openSettings() {
        openPopover()
    }

    @objc private func quitApp() {
        closePopover()
        NSApplication.shared.terminate(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        guard let closedWindow = notification.object as? NSWindow else { return }
        if closedWindow === updateWindow {
            updateDownloader?.cancel()
            updateDownloader = nil
            updateWindow = nil
        }
    }

    #if DEBUG
    @MainActor
    private func renderScreenshotsAndExit() {
        let outputDir = ProcessInfo.processInfo.environment["DOCKFLOW_SCREENSHOT_DIR"]
            ?? NSTemporaryDirectory().appending("dockflow_screenshots")
        try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)

        let shots: [(PopoverTab, String)] = [
            (.rules, "popover_rules.png"),
            (.exclusions, "popover_exclusions.png"),
            (.system, "popover_system.png")
        ]

        for (tab, filename) in shots {
            let win = NSWindow(
                contentRect: NSRect(x: 200, y: 150, width: 446, height: 420),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            win.backgroundColor = .clear
            win.isOpaque = false
            let host = NSHostingView(rootView: SettingsView(initialTab: tab))
            win.contentView = host
            win.setContentSize(host.fittingSize)
            win.makeKeyAndOrderFront(nil)

            RunLoop.current.run(until: Date().addingTimeInterval(0.35))
            host.layoutSubtreeIfNeeded()
            win.setContentSize(host.fittingSize)

            if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: rep)
                if let data = rep.representation(using: .png, properties: [:]) {
                    try? data.write(to: URL(fileURLWithPath: "\(outputDir)/\(filename)"))
                }
            }
            win.close()
        }

        exit(0)
    }
    #endif
}
