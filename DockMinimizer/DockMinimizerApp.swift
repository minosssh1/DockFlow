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

// MARK: - Modern Settings View (macOS 27 Aesthetic)

struct SettingsView: View {
    @AppStorage("loggingEnabled") private var loggingEnabled = false
    @AppStorage("showPanelOnLaunch") private var showPanelOnLaunch = false
    @AppStorage("quitOnCloseButton") private var quitOnCloseButton = true
    @StateObject private var launchAtLoginManager = LaunchAtLoginManager.shared
    @StateObject private var dockMonitor = DockMonitor.shared

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
                            iconName: "xmark.circle.fill",
                            iconColor: .red,
                            title: "Полное закрытие по крестику (⌘Q)",
                            subtitle: "Завершает приложение, когда закрывается его последнее окно. Вкладки сохраняются!"
                        ) {
                            Toggle("", isOn: $quitOnCloseButton)
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

                    // Section 2: Системные настройки
                    VStack(spacing: 0) {
                        SettingRow(
                            iconName: "bolt.fill",
                            iconColor: .green,
                            title: "Запуск при входе в систему",
                            subtitle: "Автоматически запускать DockMinimizer при включении Mac"
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
                Text("DockFlow v1.0.4 • Fork of DockMinimizer")
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
        .frame(width: 440, height: 560)
        .background(Color(NSColor.windowBackgroundColor))
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
        .defaultSize(width: 440, height: 560)
        .commands {
            CommandGroup(replacing: .windowArrangement) { }
        }
        .defaultLaunchBehavior(.suppressed)
    }
}
