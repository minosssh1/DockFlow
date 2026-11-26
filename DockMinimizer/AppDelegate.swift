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

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, UNUserNotificationCenterDelegate {
    var statusItem: NSStatusItem?
    var dockMonitor: DockMonitor?
    private var permissionAlertShown = false
    private var settingsWindow: NSWindow?
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

        LocalizationManager.shared.$currentLanguage
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updateStatusItemMenu()
                }
            }
            .store(in: &cancellables)

        checkAccessibilityPermission()

        dockMonitor = DockMonitor.shared
        AutoQuitter.shared.start()

        let hasKey = UserDefaults.standard.object(forKey: "showPanelOnLaunch") != nil
        let showPanelOnLaunch = hasKey ? UserDefaults.standard.bool(forKey: "showPanelOnLaunch") : false
        if showPanelOnLaunch {
            openSettings()
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
                    self?.updateStatusItemMenu()
                }
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

        button.title = "▼"
        button.font = NSFont.systemFont(ofSize: 14)
        button.toolTip = "DockFlow"

        updateStatusItemMenu()

        item.isVisible = true
        button.isHidden = false
    }

    private func updateStatusItemMenu() {
        guard let item = self.statusItem else { return }

        let menu = NSMenu()

        let settingsItem = NSMenuItem(title: L10n.settings, action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let statusMenuItem = NSMenuItem(title: L10n.dockFlowActive, action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        let quitOnCloseKey = "quitOnCloseButton"
        let isQuitOnClose = UserDefaults.standard.object(forKey: quitOnCloseKey) == nil || UserDefaults.standard.bool(forKey: quitOnCloseKey)
        let quitOnCloseItem = NSMenuItem(title: L10n.quitOnCloseMenu, action: #selector(toggleQuitOnClose), keyEquivalent: "")
        quitOnCloseItem.target = self
        quitOnCloseItem.state = isQuitOnClose ? .on : .off
        menu.addItem(quitOnCloseItem)

        menu.addItem(NSMenuItem.separator())

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
        if updateService.updateAvailable {
            updateItem.state = .on
        }
        menu.addItem(updateItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: L10n.quit, action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
    }

    @objc private func toggleQuitOnClose() {
        let key = "quitOnCloseButton"
        let current = UserDefaults.standard.object(forKey: key) == nil || UserDefaults.standard.bool(forKey: key)
        UserDefaults.standard.set(!current, forKey: key)
        updateStatusItemMenu()
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
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                                self?.updateWindow?.close()
                                self?.updateWindow = nil
                                self?.updateDownloader = nil
                                self?.updateService.applyUpdateAndRestart(dmgPath: stagedDMG.path)
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
        NSApplication.shared.activate(ignoringOtherApps: true)

        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let screenVisibleHeight = NSScreen.main?.visibleFrame.height ?? 760
        let targetHeight = min(740, max(520, screenVisibleHeight - 40))

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: targetHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.settingsWindowTitle
        window.minSize = NSSize(width: 460, height: 500)
        window.maxSize = NSSize(width: 460, height: 820)
        window.center()
        window.contentView = NSHostingView(rootView: SettingsView(onClose: { [weak window] in
            window?.close()
        }))
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        settingsWindow = window
    }

    @objc private func quitApp() {
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

        let win1 = NSWindow(
            contentRect: NSRect(x: 200, y: 150, width: 460, height: 720),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win1.title = L10n.settingsWindowTitle
        let host1 = NSHostingView(rootView: SettingsView())
        win1.contentView = host1
        win1.makeKeyAndOrderFront(nil)

        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        host1.layoutSubtreeIfNeeded()

        if let frameView = win1.contentView?.superview,
           let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) {
            frameView.cacheDisplay(in: frameView.bounds, to: rep)
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: URL(fileURLWithPath: "\(outputDir)/settings_main.png"))
            }
        }
        win1.close()

        let win2 = NSWindow(
            contentRect: NSRect(x: 200, y: 150, width: 480, height: 460),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win2.title = L10n.exclusionsWindowTitle
        let host2 = NSHostingView(rootView: ExclusionsSheetView())
        win2.contentView = host2
        win2.makeKeyAndOrderFront(nil)

        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        host2.layoutSubtreeIfNeeded()

        if let frameView = win2.contentView?.superview,
           let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) {
            frameView.cacheDisplay(in: frameView.bounds, to: rep)
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: URL(fileURLWithPath: "\(outputDir)/settings_exclusions.png"))
            }
        }
        win2.close()

        exit(0)
    }
    #endif
}
