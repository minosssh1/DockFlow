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

// MARK: - V2.1 Graphite Precision Theme

enum PopoverTab: String, CaseIterable {
    case rules
    case exclusions
    case system
}

/// Holds ephemeral UI state and M3/T4 layout dimensions without relying on SwiftUI `@State` macros.
final class PopoverUIState: ObservableObject {
    @Published var selectedTab: PopoverTab
    @Published var didPerformManualCheck: Bool = false
    @Published var isPanelPresented: Bool
    @Published var targetTotalHeight: CGFloat

    init(initialTab: PopoverTab = .rules, isPanelPresented: Bool = true, targetTotalHeight: CGFloat = 427) {
        self.selectedTab = initialTab
        self.isPanelPresented = isPanelPresented
        self.targetTotalHeight = targetTotalHeight
    }
}

/// Soft blur + opacity + vertical lift modifier for silky tab transitions.
private struct BlurFadeModifier: ViewModifier {
    let blurRadius: CGFloat
    let opacity: Double
    let yOffset: CGFloat
    let scale: CGFloat

    func body(content: Content) -> some View {
        content
            .blur(radius: blurRadius)
            .opacity(opacity)
            .offset(y: yOffset)
            .scaleEffect(scale)
    }
}

/// Lightweight hover tracker for subtle Apple-precision card & toggle highlights under bare `swiftc`.
private final class HoverTracker: ObservableObject {
    @Published var isHovered: Bool = false
}

/// Smooth tactile press feedback for buttons, chips, and segmented controls (Refined I3).
private struct GraphitePressButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.968
    var pressedOpacity: Double = 0.86

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1.0)
            .opacity(configuration.isPressed ? pressedOpacity : 1.0)
            .animation(
                configuration.isPressed
                    ? .spring(response: 0.16, dampingFraction: 0.85)
                    : .spring(response: 0.30, dampingFraction: 0.76),
                value: configuration.isPressed
            )
    }
}

/// Interactive pill-stretch toggle style for silky macOS/iOS-grade switch physics (Refined I3).
private struct GraphiteToggleButtonStyle: ButtonStyle {
    let isOn: Bool
    let theme: GraphiteTheme
    let isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        let knobWidth: CGFloat = configuration.isPressed ? 18.5 : 14.0
        let travel: CGFloat = 32.0 - 4.0 - knobWidth
        let knobOffset: CGFloat = isOn ? (travel / 2.0) : -(travel / 2.0)

        let trackFill: Color = {
            if isOn {
                return configuration.isPressed ? theme.activeFill.opacity(0.88) : theme.activeFill
            } else {
                return isHovered ? theme.trackHoverOff : theme.trackOff
            }
        }()

        return Capsule(style: .continuous)
            .fill(trackFill)
            .frame(width: 32, height: 18)
            .overlay(
                Capsule(style: .continuous)
                    .fill(isOn ? theme.activeText : Color.white.opacity(0.95))
                    .frame(width: knobWidth, height: 14)
                    .shadow(color: .black.opacity(0.22), radius: 1.5, x: 0, y: 0.8)
                    .offset(x: knobOffset)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeOut(duration: 0.22), value: isOn)
            .animation(.easeOut(duration: 0.14), value: isHovered)
            .animation(.spring(response: 0.28, dampingFraction: 0.78), value: configuration.isPressed)
            .animation(.spring(response: 0.32, dampingFraction: 0.78), value: isOn)
    }
}

private struct GraphiteTheme {
    let isDark: Bool

    var canvasBackground: Color {
        isDark
            ? Color.black.opacity(0.10)
            : Color.white.opacity(0.14)
    }

    var wellFill: Color {
        isDark
            ? Color.white.opacity(0.065)
            : Color.white.opacity(0.38)
    }

    var wellBorder: Color {
        isDark ? Color.white.opacity(0.11) : Color.black.opacity(0.08)
    }

    var wellHoverBorder: Color {
        isDark ? Color.white.opacity(0.24) : Color.black.opacity(0.18)
    }

    var hairline: Color {
        isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.09)
    }

    var activeFill: Color {
        isDark ? Color(white: 0.94) : Color(white: 0.11)
    }

    var activeText: Color {
        isDark ? Color(white: 0.06) : Color.white
    }

    var primaryText: Color {
        isDark ? Color.white.opacity(0.94) : Color(white: 0.09)
    }

    var secondaryText: Color {
        isDark ? Color.white.opacity(0.55) : Color.black.opacity(0.54)
    }

    var trackOff: Color {
        isDark ? Color.white.opacity(0.16) : Color.black.opacity(0.15)
    }

    var trackHoverOff: Color {
        isDark ? Color.white.opacity(0.22) : Color.black.opacity(0.20)
    }

    var axActiveDot: Color {
        Color(red: 74/255, green: 222/255, blue: 128/255).opacity(0.85)
    }

    var axMissingDot: Color {
        Color(red: 245/255, green: 158/255, blue: 11/255).opacity(0.88)
    }

    func bodyFont(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Avenir Next", size: size).weight(weight)
    }
}

// MARK: - Graphite Monochrome Toggle (Refined I3)

private struct GraphiteToggle: View {
    @Binding var isOn: Bool
    let theme: GraphiteTheme
    @ObservedObject private var hoverTracker = HoverTracker()

    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                isOn.toggle()
            }
        }) {
            EmptyView()
        }
        .buttonStyle(GraphiteToggleButtonStyle(isOn: isOn, theme: theme, isHovered: hoverTracker.isHovered))
        .onHover { hovering in
            hoverTracker.isHovered = hovering
        }
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn ? "1" : "0")
    }
}

// MARK: - Graphite Row Component (Refined I3 Hover)

private struct GraphiteRuleCard<Trailing: View>: View {
    let title: String
    let subtitle: String
    let theme: GraphiteTheme
    let trailing: Trailing
    @ObservedObject private var hoverTracker = HoverTracker()

    init(
        title: String,
        subtitle: String,
        theme: GraphiteTheme,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.theme = theme
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(theme.bodyFont(12.5, weight: .semibold))
                    .foregroundColor(theme.primaryText)

                Text(subtitle)
                    .font(theme.bodyFont(11))
                    .foregroundColor(theme.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            trailing
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(theme.wellFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(hoverTracker.isHovered ? theme.wellHoverBorder : theme.wellBorder, lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.16), value: hoverTracker.isHovered)
        .onHover { hovering in
            hoverTracker.isHovered = hovering
        }
    }
}

// MARK: - Settings Popover View (V2.1 Matte Baseline)

struct SettingsView: View {
    var initialTab: PopoverTab = .rules
    var fixedCanvasHeight: CGFloat? = nil
    var onSelectTab: ((PopoverTab) -> Void)? = nil
    var onContentChanged: (() -> Void)? = nil
    var onPickExcludedApp: (() -> Void)? = nil
    var onCheckForUpdates: (() -> Void)? = nil
    var onInstallUpdate: (() -> Void)? = nil
    var onOpenLogs: (() -> Void)? = nil
    var onOpenAccessibilitySettings: (() -> Void)? = nil
    var onQuit: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var tabNamespace
    @Namespace private var skmNamespace
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

    @ObservedObject private var uiState: PopoverUIState

    init(
        initialTab: PopoverTab = .rules,
        uiState: PopoverUIState? = nil,
        fixedCanvasHeight: CGFloat? = nil,
        onSelectTab: ((PopoverTab) -> Void)? = nil,
        onContentChanged: (() -> Void)? = nil,
        onPickExcludedApp: (() -> Void)? = nil,
        onCheckForUpdates: (() -> Void)? = nil,
        onInstallUpdate: (() -> Void)? = nil,
        onOpenLogs: (() -> Void)? = nil,
        onOpenAccessibilitySettings: (() -> Void)? = nil,
        onQuit: (() -> Void)? = nil
    ) {
        self.initialTab = initialTab
        self.fixedCanvasHeight = fixedCanvasHeight
        self.onSelectTab = onSelectTab
        self.onContentChanged = onContentChanged
        self.onPickExcludedApp = onPickExcludedApp
        self.onCheckForUpdates = onCheckForUpdates
        self.onInstallUpdate = onInstallUpdate
        self.onOpenLogs = onOpenLogs
        self.onOpenAccessibilitySettings = onOpenAccessibilitySettings
        self.onQuit = onQuit
        _uiState = ObservedObject(wrappedValue: uiState ?? PopoverUIState(initialTab: initialTab))
    }

    private var theme: GraphiteTheme {
        GraphiteTheme(isDark: colorScheme == .dark)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.2.0"
    }

    private var tabBlurTransition: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: BlurFadeModifier(blurRadius: 3.5, opacity: 0, yOffset: 5, scale: 0.988),
                identity: BlurFadeModifier(blurRadius: 0, opacity: 1, yOffset: 0, scale: 1.0)
            ),
            removal: .modifier(
                active: BlurFadeModifier(blurRadius: 3.0, opacity: 0, yOffset: -3, scale: 0.992),
                identity: BlurFadeModifier(blurRadius: 0, opacity: 1, yOffset: 0, scale: 1.0)
            )
        )
    }

    var body: some View {
        let card = VStack(spacing: 0) {
            headerBar

            Rectangle()
                .fill(theme.hairline)
                .frame(height: 1)

            VStack(spacing: 0) {
                ZStack(alignment: .top) {
                    switch uiState.selectedTab {
                    case .rules:
                        rulesTab
                            .transition(tabBlurTransition)
                    case .exclusions:
                        exclusionsTab
                            .transition(tabBlurTransition)
                    case .system:
                        systemTab
                            .transition(tabBlurTransition)
                    }
                }
                .clipped()
                .padding(.bottom, 12)

                if fixedCanvasHeight != nil {
                    Spacer(minLength: 0)
                }

                footerBar
            }
            .padding(14)
        }
        .frame(width: 446)
        .frame(height: fixedCanvasHeight != nil ? uiState.targetTotalHeight : nil, alignment: .top)
        .blur(radius: uiState.isPanelPresented ? 0 : 3.0)
        .scaleEffect(uiState.isPanelPresented ? 1.0 : 0.985, anchor: .top)
        .opacity(uiState.isPanelPresented ? 1.0 : 0.0)
        .onAppear {
            launchAtLoginManager.refreshStatus()
        }
        .onChange(of: exclusionManager.excludedBundleIDs.count) { _, _ in
            onContentChanged?()
        }
        .onChange(of: lm.currentLanguage) { _, _ in
            onContentChanged?()
        }
        .onChange(of: updateService.updateAvailable) { _, _ in
            onContentChanged?()
        }

        Group {
            if let fixedCanvasHeight {
                card
                    .frame(width: 446, height: fixedCanvasHeight, alignment: .top)
            } else {
                card
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .background(theme.canvasBackground)
        .ignoresSafeArea()
    }

    // MARK: Header & Segmented Capsule Tabs

    private var headerBar: some View {
        HStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("DockFlow")
                    .font(theme.bodyFont(13.5, weight: .bold))
                    .foregroundColor(theme.primaryText)

                Text("v\(appVersion)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(theme.secondaryText)
            }

            Spacer(minLength: 8)

            HStack(spacing: 2) {
                tabButton(.rules, label: L10n.tabRules, showDot: false)
                tabButton(.exclusions, label: "\(L10n.tabExclusions) (\(exclusionManager.excludedBundleIDs.count))", showDot: false)
                tabButton(.system, label: L10n.tabSystem, showDot: updateService.updateAvailable)
            }
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(theme.wellFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(theme.wellBorder, lineWidth: 1)
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func switchToTab(_ tab: PopoverTab) {
        if let onSelectTab {
            onSelectTab(tab)
        } else {
            withAnimation(.timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.34)) {
                uiState.selectedTab = tab
            }
        }
    }

    private func tabButton(_ tab: PopoverTab, label: String, showDot: Bool) -> some View {
        let isSelected = uiState.selectedTab == tab
        return Button(action: {
            switchToTab(tab)
        }) {
            HStack(spacing: 4) {
                Text(label)
                    .font(theme.bodyFont(11.5, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)

                if showDot {
                    Circle()
                        .fill(isSelected ? theme.activeText : theme.axActiveDot)
                        .frame(width: 5, height: 5)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                        .fill(theme.activeFill)
                        .matchedGeometryEffect(id: "activeTabPill", in: tabNamespace)
                }
            }
            .foregroundColor(isSelected ? theme.activeText : theme.secondaryText)
            .contentShape(Rectangle())
        }
        .buttonStyle(GraphitePressButtonStyle(pressedScale: 0.96, pressedOpacity: 0.90))
    }

    // MARK: Tab 1 — Rules

    private var rulesTab: some View {
        VStack(spacing: 8) {
            GraphiteRuleCard(
                title: L10n.genieTitle,
                subtitle: L10n.genieSubtitle,
                theme: theme
            ) {
                GraphiteToggle(isOn: $genieMinimizeEnabled, theme: theme)
            }

            GraphiteRuleCard(
                title: L10n.quitOnCloseTitle,
                subtitle: L10n.quitOnCloseSubtitle,
                theme: theme
            ) {
                GraphiteToggle(isOn: $quitOnCloseButton, theme: theme)
            }

            GraphiteRuleCard(
                title: L10n.hapticTitle,
                subtitle: L10n.hapticSubtitle,
                theme: theme
            ) {
                GraphiteToggle(isOn: $hapticService.isEnabled, theme: theme)
            }

            // Middle-Click Segmented Selector (Refined I3 Glider)
            VStack(alignment: .leading, spacing: 7) {
                Text(L10n.middleClickTitle)
                    .font(theme.bodyFont(12, weight: .semibold))
                    .foregroundColor(theme.primaryText)

                HStack(spacing: 4) {
                    middleOptionButton("newWindow", title: L10n.middleClickNewWindowShort)
                    middleOptionButton("quitApp", title: L10n.middleClickQuitShort)
                    middleOptionButton("hideApp", title: L10n.middleClickHideShort)
                    middleOptionButton("disabled", title: L10n.middleClickOffShort)
                }
                .padding(3)
                .background(
                    RoundedRectangle(cornerRadius: 8.5, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(theme.wellFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(theme.wellBorder, lineWidth: 1)
            )
        }
    }

    private func middleOptionButton(_ tag: String, title: String) -> some View {
        let isSelected = middleClickAction == tag
        return Button(action: {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                middleClickAction = tag
            }
        }) {
            Text(title)
                .font(theme.bodyFont(11, weight: isSelected ? .semibold : .medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                            .fill(theme.activeFill)
                            .matchedGeometryEffect(id: "skmPill", in: skmNamespace)
                    }
                }
                .foregroundColor(isSelected ? theme.activeText : theme.secondaryText)
                .contentShape(Rectangle())
        }
        .buttonStyle(GraphitePressButtonStyle(pressedScale: 0.96, pressedOpacity: 0.90))
    }

    // MARK: Tab 2 — Exclusions

    private var exclusionsTab: some View {
        let items = exclusionManager.excludedAppItems
        let telegramID = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.tdesktop.Telegram") != nil
            ? "com.tdesktop.Telegram"
            : "ru.keepcoder.Telegram"
        let presets: [(String, String)] = [
            ("Telegram", telegramID),
            ("Discord", "com.hnc.Discord"),
            ("Spotify", "com.spotify.client"),
            (L10n.musicPreset, "com.apple.Music")
        ]

        return VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Text(L10n.exclusionsHeaderSubtitle)
                    .font(theme.bodyFont(11))
                    .foregroundColor(theme.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 4)

                Button(action: {
                    if let onPickExcludedApp {
                        onPickExcludedApp()
                    } else {
                        exclusionManager.addAppViaFilePicker()
                    }
                }) {
                    Text("+ \(L10n.addApplication)")
                        .font(theme.bodyFont(11.5, weight: .semibold))
                        .fixedSize()
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(theme.wellFill)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(theme.wellBorder, lineWidth: 1)
                        )
                    .foregroundColor(theme.primaryText)
                    .contentShape(Rectangle())
                }
                .buttonStyle(GraphitePressButtonStyle())
            }

            if items.isEmpty {
                VStack(spacing: 6) {
                    Text(L10n.exclusionsEmptyTitle)
                        .font(theme.bodyFont(12.5, weight: .semibold))
                        .foregroundColor(theme.primaryText)
                    Text(L10n.exclusionsEmptySubtitle)
                        .font(theme.bodyFont(11))
                        .foregroundColor(theme.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 140)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(theme.wellFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(theme.wellBorder, lineWidth: 1)
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(items) { item in
                            HStack(spacing: 10) {
                                Image(nsImage: item.icon)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 24, height: 24)
                                    .cornerRadius(6)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.name)
                                        .font(theme.bodyFont(12, weight: .semibold))
                                        .foregroundColor(theme.primaryText)
                                    Text(item.bundleIdentifier)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(theme.secondaryText)
                                        .lineLimit(1)
                                }

                                Spacer()

                                Button(action: {
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                                        exclusionManager.removeApp(bundleIdentifier: item.bundleIdentifier)
                                    }
                                }) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(theme.secondaryText)
                                        .frame(width: 24, height: 24)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(GraphitePressButtonStyle(pressedScale: 0.88, pressedOpacity: 0.7))
                                .help(L10n.deleteHelp)
                            }
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(theme.wellFill)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(theme.wellBorder, lineWidth: 1)
                            )
                            .transition(
                                .asymmetric(
                                    insertion: .opacity.combined(with: .scale(scale: 0.96)),
                                    removal: .opacity.combined(with: .scale(scale: 0.94))
                                )
                            )
                        }
                    }
                    .animation(.spring(response: 0.28, dampingFraction: 0.85), value: items)
                }
                .frame(maxHeight: 168)
            }

            // Presets Row
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.quickAdd)
                    .font(theme.bodyFont(11))
                    .foregroundColor(theme.secondaryText)

                HStack(spacing: 6) {
                    ForEach(presets, id: \.1) { name, bid in
                        let isIncluded = exclusionManager.isExcluded(bundleIdentifier: bid)
                        Button(action: {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                                if isIncluded {
                                    exclusionManager.removeApp(bundleIdentifier: bid)
                                } else {
                                    exclusionManager.addApp(bundleIdentifier: bid)
                                }
                            }
                        }) {
                            Text(isIncluded ? "✓ \(name)" : "+ \(name)")
                                .font(theme.bodyFont(11, weight: isIncluded ? .semibold : .regular))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4.5)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(isIncluded ? theme.activeFill : theme.wellFill)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .stroke(isIncluded ? Color.clear : theme.wellBorder, lineWidth: 1)
                                )
                                .foregroundColor(isIncluded ? theme.activeText : theme.secondaryText)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(GraphitePressButtonStyle(pressedScale: 0.96, pressedOpacity: 0.88))
                    }
                }
            }
        }
    }

    // MARK: Tab 3 — System & OTA

    private var systemTab: some View {
        VStack(spacing: 10) {
            // OTA Card
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    if updateService.isChecking {
                        Text(L10n.checkingNow)
                            .font(theme.bodyFont(12.5, weight: .semibold))
                            .foregroundColor(theme.primaryText)
                    } else if updateService.updateAvailable, let latest = updateService.latestVersion {
                        Text(L10n.otaReadyTitle(version: latest))
                            .font(theme.bodyFont(12.5, weight: .semibold))
                            .foregroundColor(theme.primaryText)
                    } else {
                        Text(L10n.otaUpToDateTitle(version: appVersion))
                            .font(theme.bodyFont(12.5, weight: .semibold))
                            .foregroundColor(theme.primaryText)
                    }

                    if let err = updateService.errorMessage, uiState.didPerformManualCheck {
                        Text(err)
                            .font(theme.bodyFont(10.5))
                            .foregroundColor(theme.axMissingDot)
                            .lineLimit(1)
                    } else {
                        Text("SHA-256 · GitHub Releases")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundColor(theme.secondaryText)
                    }
                }

                Spacer()

                if updateService.updateAvailable {
                    Button(action: {
                        onInstallUpdate?()
                    }) {
                        Text(L10n.updateNow)
                            .font(theme.bodyFont(11.5, weight: .semibold))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.activeFill))
                            .foregroundColor(theme.activeText)
                    }
                    .buttonStyle(GraphitePressButtonStyle())
                } else {
                    Button(action: {
                        uiState.didPerformManualCheck = true
                        onCheckForUpdates?()
                    }) {
                        HStack(spacing: 5) {
                            if updateService.isChecking {
                                ProgressView()
                                    .controlSize(.mini)
                            }
                            Text(L10n.checkNow)
                                .font(theme.bodyFont(11.5, weight: .semibold))
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.wellFill))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(theme.wellBorder, lineWidth: 1))
                        .foregroundColor(theme.primaryText)
                    }
                    .buttonStyle(GraphitePressButtonStyle())
                    .disabled(updateService.isChecking)
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(theme.wellFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(theme.wellBorder, lineWidth: 1)
            )

            // Grouped System Controls
            VStack(spacing: 0) {
                systemRow(title: L10n.launchAtLoginTitle) {
                    GraphiteToggle(
                        isOn: Binding(
                            get: { launchAtLoginManager.isEnabled },
                            set: { launchAtLoginManager.setEnabled($0) }
                        ),
                        theme: theme
                    )
                }

                rowDivider

                systemRow(title: L10n.showPanelOnLaunchTitle) {
                    GraphiteToggle(isOn: $showPanelOnLaunch, theme: theme)
                }

                rowDivider

                systemRow(title: L10n.updatePolicyTitle) {
                    Picker("", selection: $updateService.checkPolicy) {
                        ForEach(UpdateCheckPolicy.allCases, id: \.self) { policy in
                            Text(policy.displayName).tag(policy)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }

                rowDivider

                systemRow(title: L10n.languageTitle) {
                    Picker("", selection: $lm.currentLanguage) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }

                rowDivider

                systemRow(title: L10n.loggingTitle) {
                    HStack(spacing: 10) {
                        Button(action: {
                            if let onOpenLogs {
                                onOpenLogs()
                            } else {
                                LogService.shared.openLogFolder()
                            }
                        }) {
                            Text(L10n.openLogsFolder)
                                .font(theme.bodyFont(11))
                                .foregroundColor(theme.secondaryText)
                                .underline()
                        }
                        .buttonStyle(GraphitePressButtonStyle(pressedScale: 0.96, pressedOpacity: 0.72))

                        GraphiteToggle(isOn: $logService.loggingEnabled, theme: theme)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(theme.wellFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(theme.wellBorder, lineWidth: 1)
            )
        }
    }

    private func systemRow<Trailing: View>(title: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack {
            Text(title)
                .font(theme.bodyFont(12, weight: .medium))
                .foregroundColor(theme.primaryText)
                .lineLimit(1)

            Spacer(minLength: 8)

            trailing()
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 8.5)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(theme.hairline)
            .frame(height: 1)
            .padding(.leading, 13)
    }

    // MARK: Unified Footer

    private var footerBar: some View {
        VStack(spacing: 9) {
            Rectangle()
                .fill(theme.hairline)
                .frame(height: 1)

            HStack {
                Button(action: {
                    if !dockMonitor.isFullyFunctional {
                        onOpenAccessibilitySettings?()
                    } else {
                        switchToTab(.system)
                    }
                }) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(dockMonitor.isFullyFunctional ? theme.axActiveDot : theme.axMissingDot)
                            .frame(width: 6.5, height: 6.5)

                        Text(dockMonitor.isFullyFunctional ? L10n.axActiveShort : L10n.axMissingShort)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(theme.secondaryText)
                    }
                }
                .buttonStyle(GraphitePressButtonStyle(pressedScale: 0.96, pressedOpacity: 0.75))

                Spacer()

                Button(action: {
                    if let onQuit {
                        onQuit()
                    } else {
                        NSApplication.shared.terminate(nil)
                    }
                }) {
                    Text("\(L10n.quitApp) (⌘Q)")
                        .font(theme.bodyFont(11.5, weight: .medium))
                        .foregroundColor(theme.secondaryText)
                }
                .buttonStyle(GraphitePressButtonStyle(pressedScale: 0.96, pressedOpacity: 0.75))
            }
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
