import SwiftUI
import Cocoa
import ServiceManagement

class LaunchAtLoginManager: ObservableObject {
    static let shared = LaunchAtLoginManager()

    @Published var isEnabled: Bool {
        didSet {
            setEnabled(isEnabled)
        }
    }

    private init() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    private func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to \(enabled ? "enable" : "disable") launch at login: \(error)")
        }
    }
}

// MARK: - Setting Row Component (macOS 27 System Style)

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
    @ObservedObject var exclusionManager = AppExclusionManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header
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
                    Text("Исключения закрытия по крестику")
                        .font(.system(size: 15, weight: .bold))
                    Text("Эти приложения не завершаются (⌘Q) при закрытии окна и продолжают работать в фоне")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)

            Divider()

            // List of excluded apps
            let items = exclusionManager.getExcludedAppItems()
            if items.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "tray")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text("Список исключений пуст")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("Все приложения будут завершаться по крестику")
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
                                .help("Удалить из исключений")
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

            // Quick Add suggestions
            let suggestions = [
                ("Telegram", "ru.keepcoder.Telegram"),
                ("Discord", "com.hnc.Discord"),
                ("Spotify", "com.spotify.client"),
                ("Музыка", "com.apple.Music")
            ].filter { !exclusionManager.isExcluded(bundleIdentifier: $0.1) }

            if !suggestions.isEmpty {
                HStack(spacing: 8) {
                    Text("Быстрое добавление:")
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

            // Bottom action buttons
            HStack {
                Button(action: {
                    exclusionManager.addAppViaFilePicker()
                }) {
                    Label("Добавить приложение...", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Spacer()

                Button("Готово") {
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

// MARK: - Modern Settings View (macOS 27 Aesthetic)

struct SettingsView: View {
    @AppStorage("loggingEnabled") private var loggingEnabled = false
    @AppStorage("showPanelOnLaunch") private var showPanelOnLaunch = false
    @AppStorage("quitOnCloseButton") private var quitOnCloseButton = true
    @AppStorage("hapticFeedbackEnabled") private var hapticFeedbackEnabled = true
    @AppStorage("middleClickAction") private var middleClickAction = "newWindow"
    @StateObject private var launchAtLoginManager = LaunchAtLoginManager.shared
    @StateObject private var dockMonitor = DockMonitor.shared
    @StateObject private var exclusionManager = AppExclusionManager.shared

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
                        .frame(width: 64, height: 64)
                        .shadow(color: Color.blue.opacity(0.4), radius: 10, x: 0, y: 5)

                    Image(systemName: "dock.rectangle")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundColor(.white)
                }
                .padding(.top, 16)

                VStack(spacing: 4) {
                    Text("DockFlow")
                        .font(.system(size: 20, weight: .bold, design: .rounded))

                    Text("Управление Доком и закрытие окон (⌘Q)")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                // Status Pill
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text("Работает в фоновом режиме")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.green.opacity(0.12))
                )
            }
            .padding(.bottom, 16)

            // Content Sections
            ScrollView {
                VStack(spacing: 16) {
                    // Section 1: Функции окон и Дока
                    VStack(spacing: 0) {
                        SettingRow(
                            iconName: "sparkles",
                            iconColor: .blue,
                            title: "Эффект Джинна в Доке",
                            subtitle: "Клик по иконке активного приложения в Доке плавно сворачивает его с анимацией"
                        ) {
                            Toggle("", isOn: .constant(true))
                                .labelsHidden()
                                .disabled(true)
                        }

                        Divider()
                            .padding(.leading, 58)

                        SettingRow(
                            iconName: "hand.tap.fill",
                            iconColor: .orange,
                            title: "Тактильный отклик (Haptic)",
                            subtitle: "Виброотклик трекпада Force Touch при сворачивании и закрытии окон"
                        ) {
                            Toggle("", isOn: $hapticFeedbackEnabled)
                                .labelsHidden()
                        }

                        Divider()
                            .padding(.leading, 58)

                        SettingRow(
                            iconName: "computermouse.fill",
                            iconColor: .teal,
                            title: "Клик колёсиком по Доку",
                            subtitle: "Действие при среднем клике по иконке приложения"
                        ) {
                            Picker("", selection: $middleClickAction) {
                                Text("Новое окно (⌘N)").tag("newWindow")
                                Text("Завершить (⌘Q)").tag("quitApp")
                                Text("Скрыть (⌘H)").tag("hideApp")
                                Text("Отключено").tag("disabled")
                            }
                            .labelsHidden()
                            .frame(width: 155)
                        }

                        Divider()
                            .padding(.leading, 58)

                        SettingRow(
                            iconName: "xmark.circle.fill",
                            iconColor: .red,
                            title: "Полное закрытие по крестику (⌘Q)",
                            subtitle: "Завершает приложение, когда закрывается его последнее окно. Вкладки сохраняются!"
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
                                title: "Исключения закрытия (⌘Q)",
                                subtitle: "\(exclusionManager.excludedBundleIDs.count) приложений остаются работать в фоне"
                            ) {
                                Button("Настроить...") {
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

                    // Section 2: Системные настройки
                    VStack(spacing: 0) {
                        SettingRow(
                            iconName: "bolt.fill",
                            iconColor: .green,
                            title: "Запуск при входе в систему",
                            subtitle: "Автоматически запускать DockFlow при включении Mac"
                        ) {
                            Toggle("", isOn: Binding(
                                get: { launchAtLoginManager.isEnabled },
                                set: { launchAtLoginManager.isEnabled = $0 }
                            ))
                            .labelsHidden()
                        }

                        Divider()
                            .padding(.leading, 58)

                        SettingRow(
                            iconName: "macwindow",
                            iconColor: .indigo,
                            title: "Показывать окно при старте",
                            subtitle: "Открывать это окно настроек при каждом запуске системы"
                        ) {
                            Toggle("", isOn: $showPanelOnLaunch)
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

                    // Section 3: Разрешение Универсального доступа
                    VStack(spacing: 0) {
                        SettingRow(
                            iconName: "hand.raised.fill",
                            iconColor: .purple,
                            title: "Универсальный доступ",
                            subtitle: dockMonitor.isFullyFunctional
                                ? "Доступ предоставлен, все системные функции активны"
                                : "Требуется разрешение для перехвата кликов по Доку"
                        ) {
                            if dockMonitor.isFullyFunctional {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.system(size: 18))
                            } else {
                                Button("Настроить") {
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
            }

            Divider()
                .padding(.top, 12)

            // Footer
            HStack {
                Text("DockFlow v1.0.5 • Fork of DockMinimizer")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Spacer()

                Button("Закрыть") {
                    NSApplication.shared.keyWindow?.close()
                }
                .controlSize(.small)
                .keyboardShortcut(.cancelAction)

                Button("Завершить") {
                    NSApplication.shared.terminate(nil)
                }
                .controlSize(.small)
                .foregroundColor(.red)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
        }
        .frame(width: 460, height: 780)
        .background(Color(NSColor.windowBackgroundColor))
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
        WindowGroup("DockFlow", id: "settings") {
            SettingsView()
        }
        .windowStyle(.automatic)
        .defaultPosition(.center)
        .defaultSize(width: 460, height: 780)
        .commands {
            CommandGroup(replacing: .windowArrangement) { }
        }
        .defaultLaunchBehavior(.suppressed)
    }
}
