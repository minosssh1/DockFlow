import Cocoa
import SwiftUI
import Combine
import os

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var statusItem: NSStatusItem?
    var dockMonitor: DockMonitor?
    private var permissionAlertShown = false
    private var settingsWindow: NSWindow?
    private var updateWindow: NSWindow?
    private var updateDownloader: UpdateDownloader?
    private var cancellables = Set<AnyCancellable>()
    private var updateService = UpdateService.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--render-screenshots") {
            renderScreenshotsAndExit()
            return
        }

        LogService.shared.log(category: "AppDelegate", message: "应用启动: \(Bundle.main.bundlePath)")

        // Set activation policy to accessory (no dock icon, but can show status bar)
        NSApplication.shared.setActivationPolicy(.accessory)

        // Create status bar item
        createStatusItem()

        // Observe language changes
        LocalizationManager.shared.$currentLanguage
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updateStatusItemMenu()
                }
            }
            .store(in: &cancellables)

        // Check for accessibility permissions
        checkAccessibilityPermission()

        // Start monitoring Dock clicks
        dockMonitor = DockMonitor.shared

        // Start AutoQuitter (Command + Q on closing last window)
        AutoQuitter.shared.start()

        // 启动时根据设置决定是否打开设置窗口 (по умолчанию false, чтобы приложение тихо работало в фоне)
        let hasKey = UserDefaults.standard.object(forKey: "showPanelOnLaunch") != nil
        let showPanelOnLaunch = hasKey ? UserDefaults.standard.bool(forKey: "showPanelOnLaunch") : false
        if showPanelOnLaunch {
            openSettings()
        }

        // 启动后延迟检查更新
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 延迟 2 秒
            await updateService.checkForUpdates()
            if updateService.updateAvailable {
                await MainActor.run {
                    self.showUpdateAvailableAlert()
                }
            }
        }

        // 监听更新状态变化
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

        DispatchQueue.main.async { [weak self] in
            let alert = NSAlert()
            alert.messageText = L10n.permissionRequiredTitle
            alert.informativeText = L10n.permissionRequiredMessage
            alert.alertStyle = .warning
            alert.addButton(withTitle: L10n.openSystemSettings)
            alert.addButton(withTitle: L10n.later)

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    private func createStatusItem() {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let item = self.statusItem else { return }
        guard let button = item.button else { return }

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

        let statusMenuItem = NSMenuItem(title: "DockFlow активен", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        let quitOnCloseKey = "quitOnCloseButton"
        let isQuitOnClose = UserDefaults.standard.object(forKey: quitOnCloseKey) == nil || UserDefaults.standard.bool(forKey: quitOnCloseKey)
        let quitOnCloseItem = NSMenuItem(title: "Закрывать по крестику (⌘Q)", action: #selector(toggleQuitOnClose), keyEquivalent: "")
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

        // 更新检查
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
        let hasPermission = AXIsProcessTrusted()

        if hasPermission {
            let alert = NSAlert()
            alert.messageText = L10n.permissionGrantedTitle
            alert.informativeText = L10n.permissionGrantedMessage
            alert.alertStyle = .informational
            alert.addButton(withTitle: L10n.ok)
            alert.runModal()
        } else {
            showPermissionAlert()
        }
    }

    @objc private func openLogFolder() {
        LogService.shared.openLogFolder()
    }

    private func showUpdateAvailableAlert() {
        LogService.shared.log(category: "UpdateService", message: "Отображение диалога обновления: доступна версия \(updateService.latestVersion ?? "?")")
        NSApplication.shared.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Доступно обновление DockFlow!"
        alert.informativeText = "Текущая версия: \(updateService.currentVersion)\nНовая версия: \(updateService.latestVersion ?? "?")\n\nХотите установить обновление сейчас?"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Обновить сейчас")
        alert.addButton(withTitle: "Позже")

        if alert.runModal() == .alertFirstButtonReturn {
            performAutoUpdate()
        }
    }

    private func performAutoUpdate() {
        guard let downloadURL = updateService.downloadURL else {
            updateService.openReleasePage()
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
        window.title = "Обновление DockFlow"
        window.contentView = hostingView
        window.level = .floating
        window.isReleasedWhenClosed = false
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
            window?.close()
            self?.updateWindow = nil
            self?.updateDownloader = nil
            self?.updateService.openReleasePage()
        }

        viewModel.stageTitle = "Этап 1 из 3: Подключение к GitHub..."
        viewModel.stageDetail = "Установка безопасного соединения..."
        viewModel.isIndeterminate = true

        downloader.onProgress = { progress, written, total in
            viewModel.isIndeterminate = false
            viewModel.progress = progress
            viewModel.stageTitle = "Этап 1 из 3: Скачивание обновления..."

            let mbWritten = Double(written) / (1024 * 1024)
            let mbTotal = Double(total) / (1024 * 1024)
            if total > 0 {
                viewModel.stageDetail = String(format: "Загружено %.1f МБ из %.1f МБ (%.0f%%)", mbWritten, mbTotal, progress * 100)
            } else {
                viewModel.stageDetail = String(format: "Загружено %.1f МБ", mbWritten)
            }
        }

        downloader.onComplete = { [weak self] result in
            switch result {
            case .success(let tempDMG):
                viewModel.stageTitle = "Этап 2 из 3: Проверка и установка..."
                viewModel.stageDetail = "Монтирование образа и замена файлов..."
                viewModel.progress = 1.0
                viewModel.isIndeterminate = true

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    viewModel.stageTitle = "Этап 3 из 3: Перезапуск..."
                    viewModel.stageDetail = "Запуск обновленной версии DockFlow..."

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self?.updateWindow?.close()
                        self?.updateWindow = nil
                        self?.updateService.applyUpdateAndRestart(dmgPath: tempDMG.path)
                    }
                }

            case .failure(let error):
                viewModel.isFailed = true
                viewModel.stageTitle = "Ошибка загрузки обновления"
                viewModel.stageDetail = error.localizedDescription
            }
        }

        viewModel.onRetry = {
            viewModel.isFailed = false
            viewModel.stageTitle = "Этап 1 из 3: Повторное подключение..."
            viewModel.stageDetail = "Инициализация..."
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

        // 如果窗口已存在，直接激活
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            return
        }

        // 通过窗口标题查找是否已有 SwiftUI 创建的窗口
        let settingsTitle = L10n.settingsWindowTitle
        if let existingWindow = NSApplication.shared.windows.first(where: { $0.title == settingsTitle }) {
            settingsWindow = existingWindow
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }

        // 创建新窗口
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "DockFlow"
        window.center()
        window.contentView = NSHostingView(rootView: SettingsView())
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
        if let window = notification.object as? NSWindow, window == settingsWindow {
            // 窗口关闭时不清除引用，下次打开时可以复用
            // 因为 isReleasedWhenClosed = false，窗口对象仍然存在
        }
    }

    // MARK: - Screenshot Generator for Repository

    @MainActor
    private func renderScreenshotsAndExit() {
        let outputDir = "/Users/minosssh1./.gemini/antigravity/scratch/DockMinimizer/assets/screenshots"
        try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

        // 1. Render Main Settings View
        let settingsView = SettingsView().frame(width: 460, height: 600)
        let renderer1 = ImageRenderer(content: settingsView)
        renderer1.scale = 2.0
        if let cgImg = renderer1.cgImage {
            let rep = NSBitmapImageRep(cgImage: cgImg)
            if let data = rep.representation(using: .png, properties: [:]) {
                let path = "\(outputDir)/settings_main.png"
                try? data.write(to: URL(fileURLWithPath: path))
                print("✅ Rendered \(path)")
            }
        }

        // 2. Render Exclusions Sheet
        let exclusionsView = ExclusionsSheetView().frame(width: 480, height: 380)
        let renderer2 = ImageRenderer(content: exclusionsView)
        renderer2.scale = 2.0
        if let cgImg = renderer2.cgImage {
            let rep = NSBitmapImageRep(cgImage: cgImg)
            if let data = rep.representation(using: .png, properties: [:]) {
                let path = "\(outputDir)/settings_exclusions.png"
                try? data.write(to: URL(fileURLWithPath: path))
                print("✅ Rendered \(path)")
            }
        }

        exit(0)
    }
}