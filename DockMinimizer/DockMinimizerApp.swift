import SwiftUI
import Cocoa
import ServiceManagement

/// Manages Launch at Login registration via SMAppService.
final class LaunchAtLoginManager: ObservableObject {
    static let shared = LaunchAtLoginManager()

    @Published var isEnabled: Bool = false

    private init() {
        refreshStatus()
    }

    func refreshStatus() {
        let actual = SMAppService.mainApp.status == .enabled
        if isEnabled != actual {
            isEnabled = actual
        }
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refreshStatus()
        } catch {
            LogService.shared.log(level: .error, category: "LaunchAtLogin", message: "Failed to \(enabled ? "enable" : "disable") launch at login: \(error.localizedDescription)")
            refreshStatus()
        }
    }
}

// MARK: - Setting Row Component

struct SettingRow<Content: View>: View {
    let iconName: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let trailing: Content

    init(
        iconName: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        @ViewBuilder trailing: () -> Content
    ) {
        self.iconName = iconName
        self.iconColor = iconColor
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(iconColor.gradient)
                    .frame(width: 32, height: 32)
                    .shadow(color: iconColor.opacity(0.3), radius: 3, x: 0, y: 2)

                Image(systemName: iconName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)

                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            trailing
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
    }
}

// MARK: - Exclusions Sheet View

struct ExclusionsSheetView: View {
    @ObservedObject var lm = LocalizationManager.shared
    @ObservedObject var exclusionManager = AppExclusionManager.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.purple.gradient)
                        .frame(width: 36, height: 36)
                    Image(systemName: "app.badge.checkmark")
                        .foregroundColor(.white)
                        .font(.system(size: 18, weight: .semibold))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.exclusionsHeaderTitle)
                        .font(.system(size: 15, weight: .bold))
                    Text(L10n.exclusionsHeaderSubtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)

            Divider()

            let items = exclusionManager.excludedAppItems
            if items.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "tray")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text(L10n.exclusionsEmptyTitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                    Text(L10n.exclusionsEmptySubtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.8))
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(items) { item in
                            HStack(spacing: 12) {
                                Image(nsImage: item.icon)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 28, height: 28)
                                    .cornerRadius(6)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                        .font(.system(size: 13, weight: .medium))
                                    Text(item.bundleIdentifier)
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Button(action: {
                                    exclusionManager.removeApp(bundleIdentifier: item.bundleIdentifier)
                                }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red.opacity(0.8))
                                        .font(.system(size: 12))
                                }
                                .buttonStyle(.plain)
                                .help(L10n.deleteHelp)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color(NSColor.controlBackgroundColor))
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                }
            }

            Divider()

            let telegramID = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.tdesktop.Telegram") != nil
                ? "com.tdesktop.Telegram"
                : "ru.keepcoder.Telegram"
            let suggestions = [
                ("Telegram", telegramID),
                ("Discord", "com.hnc.Discord"),
                ("Spotify", "com.spotify.client"),
                (L10n.musicPreset, "com.apple.Music")
            ].filter { !exclusionManager.isExcluded(bundleIdentifier: $0.1) }

            if !suggestions.isEmpty {
                HStack(spacing: 8) {
                    Text(L10n.quickAdd)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    ForEach(suggestions, id: \.1) { name, bid in
                        Button("+ \(name)") {
                            exclusionManager.addApp(bundleIdentifier: bid)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))

                Divider()
            }

            HStack {
                Button(action: {
                    exclusionManager.addAppViaFilePicker()
                }) {
                    Label(L10n.addApplication, systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Spacer()

                Button(L10n.done) {
                    exclusionManager.showSheet = false
                }
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 480, height: 460)
    }
}

// MARK: - Settings View

struct SettingsView: View {
    var onClose: (() -> Void)? = nil

    @ObservedObject private var lm = LocalizationManager.shared
    @ObservedObject private var launchAtLoginManager = LaunchAtLoginManager.shared
    @ObservedObject private var dockMonitor = DockMonitor.shared
    @ObservedObject private var exclusionManager = AppExclusionManager.shared
    @ObservedObject private var hapticService = HapticFeedbackService.shared
    @ObservedObject private var logService = LogService.shared
    @ObservedObject private var updateService = UpdateService.shared

    @AppStorage("genieMinimizeEnabled") private var genieMinimizeEnabled = true
    @AppStorage("showPanelOnLaunch") private var showPanelOnLaunch = false
    @AppStorage("quitOnCloseButton") private var quitOnCloseButton = true
    @AppStorage("middleClickAction") private var middleClickAction = "newWindow"

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0.0"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header Card
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.blue, Color.purple, Color.indigo],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 60, height: 60)
                        .shadow(color: Color.blue.opacity(0.4), radius: 10, x: 0, y: 5)

                    Image(systemName: "dock.rectangle")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundColor(.white)
                }
                .padding(.top, 14)

                VStack(spacing: 4) {
                    Text("DockFlow")
                        .font(.system(size: 20, weight: .bold, design: .rounded))

                    Text(L10n.subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 6) {
                    Circle()
                        .fill(dockMonitor.isFullyFunctional ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(L10n.runningInBackground)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill((dockMonitor.isFullyFunctional ? Color.green : Color.orange).opacity(0.12))
                )
            }
            .padding(.bottom, 12)

            // Content Sections
            ScrollView {
                VStack(spacing: 14) {
                    // Section 1: Window & Dock Behavior
                    VStack(spacing: 0) {
                        SettingRow(
                            iconName: "sparkles",
                            iconColor: .blue,
                            title: L10n.genieTitle,
                            subtitle: L10n.genieSubtitle
                        ) {
                            Toggle("", isOn: $genieMinimizeEnabled)
                                .labelsHidden()
                        }

                        Divider()
                            .padding(.leading, 58)

                        SettingRow(
                            iconName: "hand.tap.fill",
                            iconColor: .orange,
                            title: L10n.hapticTitle,
                            subtitle: L10n.hapticSubtitle
                        ) {
                            Toggle("", isOn: $hapticService.isEnabled)
                                .labelsHidden()
                        }

                        Divider()
                            .padding(.leading, 58)

                        SettingRow(
                            iconName: "computermouse.fill",
                            iconColor: .teal,
                            title: L10n.middleClickTitle,
                            subtitle: L10n.middleClickSubtitle
                        ) {
                            Picker("", selection: $middleClickAction) {
                                Text(L10n.middleClickNewWindow).tag("newWindow")
                                Text(L10n.middleClickQuitApp).tag("quitApp")
                                Text(L10n.middleClickHideApp).tag("hideApp")
                                Text(L10n.middleClickDisabled).tag("disabled")
                            }
                            .labelsHidden()
                            .frame(width: 155)
                        }

                        Divider()
                            .padding(.leading, 58)

                        SettingRow(
                            iconName: "xmark.circle.fill",
                            iconColor: .red,
                            title: L10n.quitOnCloseTitle,
                            subtitle: L10n.quitOnCloseSubtitle
                        ) {
                            Toggle("", isOn: $quitOnCloseButton)
                                .labelsHidden()
                        }

                        if quitOnCloseButton {
                            Divider()
                                .padding(.leading, 58)

                            SettingRow(
                                iconName: "app.badge.checkmark",
                                iconColor: .purple,
                                title: L10n.exclusionsTitle,
                                subtitle: L10n.exclusionsSubtitle(count: exclusionManager.excludedBundleIDs.count)
                            ) {
                                Button(L10n.configure) {
                                    exclusionManager.showSheet = true
                                }
                                .controlSize(.small)
                            }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(NSColor.controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                    )

                    // Section 2: System, Updates & Diagnostics
                    VStack(spacing: 0) {
                        SettingRow(
                            iconName: "bolt.fill",
                            iconColor: .green,
                            title: L10n.launchAtLoginTitle,
                            subtitle: L10n.launchAtLoginSubtitle
                        ) {
                            Toggle("", isOn: Binding(
                                get: { launchAtLoginManager.isEnabled },
                                set: { launchAtLoginManager.setEnabled($0) }
                            ))
                            .labelsHidden()
                        }

                        Divider()
                            .padding(.leading, 58)

                        SettingRow(
                            iconName: "macwindow",
                            iconColor: .indigo,
                            title: L10n.showPanelOnLaunchTitle,
                            subtitle: L10n.showPanelOnLaunchSubtitle
                        ) {
                            Toggle("", isOn: $showPanelOnLaunch)
                                .labelsHidden()
                        }

                        Divider()
                            .padding(.leading, 58)

                        SettingRow(
                            iconName: "globe",
                            iconColor: .cyan,
                            title: L10n.languageTitle,
                            subtitle: L10n.languageSubtitle
                        ) {
                            Picker("", selection: $lm.currentLanguage) {
                                ForEach(AppLanguage.allCases) { lang in
                                    Text(lang.displayName).tag(lang)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 155)
                        }

                        Divider()
                            .padding(.leading, 58)

                        SettingRow(
                            iconName: "arrow.triangle.2.circlepath",
                            iconColor: .blue,
                            title: L10n.updatePolicyTitle,
                            subtitle: L10n.updatePolicySubtitle
                        ) {
                            Picker("", selection: $updateService.checkPolicy) {
                                ForEach(UpdateCheckPolicy.allCases, id: \.self) { policy in
                                    Text(policy.displayName).tag(policy)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 155)
                        }

                        Divider()
                            .padding(.leading, 58)

                        SettingRow(
                            iconName: "doc.text.magnifyingglass",
                            iconColor: .gray,
                            title: L10n.loggingTitle,
                            subtitle: L10n.loggingSubtitle
                        ) {
                            Toggle("", isOn: $logService.loggingEnabled)
                                .labelsHidden()
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(NSColor.controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                    )

                    // Section 3: Accessibility Permission
                    VStack(spacing: 0) {
                        SettingRow(
                            iconName: "hand.raised.fill",
                            iconColor: .purple,
                            title: L10n.accessibilityTitle,
                            subtitle: dockMonitor.isFullyFunctional
                                ? L10n.accessibilityGranted
                                : L10n.accessibilityRequired
                        ) {
                            if dockMonitor.isFullyFunctional {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.system(size: 18))
                            } else {
                                Button(L10n.setup) {
                                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                        NSWorkspace.shared.open(url)
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(NSColor.controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                    )
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }

            Divider()

            // Footer
            HStack {
                Text("DockFlow v\(appVersion) • Fork of DockMinimizer")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Spacer()

                Button(L10n.close) {
                    if let onClose {
                        onClose()
                    } else {
                        NSApplication.shared.windows.first(where: { $0.title == L10n.settingsWindowTitle })?.close()
                    }
                }
                .controlSize(.small)
                .keyboardShortcut(.cancelAction)

                Button(L10n.quitApp) {
                    NSApplication.shared.terminate(nil)
                }
                .controlSize(.small)
                .foregroundColor(.red)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
        }
        .frame(width: 460)
        .frame(minHeight: 500, idealHeight: 680, maxHeight: 760)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            launchAtLoginManager.refreshStatus()
        }
        .sheet(isPresented: $exclusionManager.showSheet) {
            ExclusionsSheetView()
        }
    }
}

// MARK: - App Main

@main
struct DockMinimizerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
