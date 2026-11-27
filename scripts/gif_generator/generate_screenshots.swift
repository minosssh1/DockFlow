import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers

// MARK: - Localization Helper for Showcase Rendering

enum ShowcaseLang: String {
    case ru
    case en
}

enum ShowcaseTab {
    case rules
    case exclusions
    case system
}

struct ExcludedMockApp: Identifiable {
    let id: String
    let name: String
    let bundleId: String
    let icon: CGImage?
    let fallbackColor: Color
    let fallbackSymbol: String
}

// MARK: - Ambient Wallpaper Backdrop

struct AmbientWallpaperView: View {
    let size: CGSize

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.14, green: 0.05, blue: 0.14),
                    Color(red: 0.08, green: 0.05, blue: 0.11),
                    Color(red: 0.05, green: 0.05, blue: 0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Warm rose / magenta diffused glow inspired by macOS wallpaper glass
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.94, green: 0.25, blue: 0.62, opacity: 0.62),
                            Color(red: 0.72, green: 0.18, blue: 0.48, opacity: 0.28),
                            .clear
                        ],
                        center: .center,
                        startRadius: 20,
                        endRadius: size.width * 0.42
                    )
                )
                .frame(width: size.width * 0.85, height: size.width * 0.85)
                .offset(x: -size.width * 0.22, y: -size.height * 0.14)
                .blur(radius: 40)

            // Secondary violet-magenta bokeh on bottom right
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.68, green: 0.22, blue: 0.64, opacity: 0.45),
                            Color(red: 0.34, green: 0.14, blue: 0.48, opacity: 0.18),
                            .clear
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: size.width * 0.38
                    )
                )
                .frame(width: size.width * 0.72, height: size.width * 0.72)
                .offset(x: size.width * 0.25, y: size.height * 0.18)
                .blur(radius: 45)

            // Subtle soft plum highlight wave across center
            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.88, green: 0.34, blue: 0.66, opacity: 0.24),
                            Color(red: 0.36, green: 0.28, blue: 0.72, opacity: 0.18)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: size.width * 0.75, height: size.height * 0.46)
                .rotationEffect(.degrees(-12))
                .blur(radius: 65)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }
}

// MARK: - App Icon Loader

@MainActor
enum IconLoader {
    static func appIcon(paths: [String]) -> CGImage? {
        for p in paths where FileManager.default.fileExists(atPath: p) {
            let icon = NSWorkspace.shared.icon(forFile: p)
            let px = 96
            guard let srgb = CGColorSpace(name: CGColorSpace.sRGB),
                  let ctx = CGContext(
                    data: nil,
                    width: px,
                    height: px,
                    bitsPerComponent: 8,
                    bytesPerRow: px * 4,
                    space: srgb,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return nil }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            icon.draw(in: NSRect(x: 0, y: 0, width: px, height: px), from: .zero, operation: .sourceOver, fraction: 1.0)
            NSGraphicsContext.restoreGraphicsState()
            return ctx.makeImage()
        }
        return nil
    }

    static func sampleExclusions(lang: ShowcaseLang) -> [ExcludedMockApp] {
        [
            ExcludedMockApp(
                id: "tg",
                name: "Telegram",
                bundleId: "ru.keepcoder.Telegram",
                icon: appIcon(paths: ["/Applications/Telegram.app"]),
                fallbackColor: Color(red: 0.18, green: 0.64, blue: 0.96),
                fallbackSymbol: "paperplane.fill"
            ),
            ExcludedMockApp(
                id: "dc",
                name: "Discord",
                bundleId: "com.hnc.Discord",
                icon: appIcon(paths: ["/Applications/Discord.app"]),
                fallbackColor: Color(red: 0.35, green: 0.40, blue: 0.95),
                fallbackSymbol: "bubble.left.and.bubble.right.fill"
            ),
            ExcludedMockApp(
                id: "sp",
                name: "Spotify",
                bundleId: "com.spotify.client",
                icon: appIcon(paths: ["/Applications/Spotify.app"]),
                fallbackColor: Color(red: 0.11, green: 0.73, blue: 0.33),
                fallbackSymbol: "dot.radiowaves.left.and.right"
            ),
            ExcludedMockApp(
                id: "mu",
                name: lang == .ru ? "Музыка" : "Music",
                bundleId: "com.apple.Music",
                icon: appIcon(paths: ["/System/Applications/Music.app", "/Applications/Music.app"]),
                fallbackColor: Color(red: 0.98, green: 0.22, blue: 0.36),
                fallbackSymbol: "music.note"
            )
        ]
    }
}

// MARK: - Pixel-Exact DockFlow v2.2.0 Glass Panel View

struct DockFlowPanelMockView: View {
    let lang: ShowcaseLang
    let tab: ShowcaseTab
    let exclusions: [ExcludedMockApp]
    let middleClickSelected: String

    private let activeFill = Color(white: 0.94)
    private let activeText = Color(white: 0.06)
    private let primaryText = Color.white.opacity(0.94)
    private let secondaryText = Color.white.opacity(0.60)
    private let wellFill = Color.white.opacity(0.085)
    private let wellBorder = Color.white.opacity(0.14)
    private let hairline = Color.white.opacity(0.14)
    private let trackOff = Color.white.opacity(0.18)
    private let axDot = Color(red: 74 / 255, green: 222 / 255, blue: 128 / 255).opacity(0.90)

    private func bodyFont(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Avenir Next", size: size).weight(weight)
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            Rectangle()
                .fill(hairline)
                .frame(height: 1)

            VStack(spacing: 0) {
                Group {
                    switch tab {
                    case .rules:
                        rulesContent
                    case .exclusions:
                        exclusionsContent
                    case .system:
                        systemContent
                    }
                }
                .padding(.bottom, 12)

                footerBar
            }
            .padding(14)
        }
        .frame(width: 446)
        .background(
            ZStack {
                // Simulated warm frosted optical glass matching NSVisualEffectView(.popover, .behindWindow)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.32, green: 0.14, blue: 0.28).opacity(0.76),
                                Color(red: 0.22, green: 0.11, blue: 0.22).opacity(0.84)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(0.16))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.28),
                            Color.white.opacity(0.10)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.45), radius: 28, x: 0, y: 16)
        .shadow(color: Color(red: 0.85, green: 0.22, blue: 0.56).opacity(0.14), radius: 36, x: 0, y: 10)
    }

    private var headerBar: some View {
        HStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("DockFlow")
                    .font(bodyFont(13.5, weight: .bold))
                    .foregroundColor(primaryText)

                Text("v2.2.0")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(secondaryText)
            }

            Spacer(minLength: 8)

            HStack(spacing: 2) {
                tabPill(lang == .ru ? "Правила" : "Rules", selected: tab == .rules)
                tabPill(lang == .ru ? "Исключения (\(exclusions.count))" : "Exclusions (\(exclusions.count))", selected: tab == .exclusions)
                tabPill(lang == .ru ? "Система" : "System", selected: tab == .system)
            }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(wellFill))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(wellBorder, lineWidth: 1))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func tabPill(_ label: String, selected: Bool) -> some View {
        Text(label)
            .font(bodyFont(11.5, weight: selected ? .semibold : .medium))
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 6.5, style: .continuous).fill(activeFill)
                }
            }
            .foregroundColor(selected ? activeText : secondaryText)
    }

    private func toggleView(isOn: Bool) -> some View {
        let knobOffset: CGFloat = isOn ? 7.0 : -7.0
        return Capsule(style: .continuous)
            .fill(isOn ? activeFill : trackOff)
            .frame(width: 32, height: 18)
            .overlay(
                Capsule(style: .continuous)
                    .fill(isOn ? activeText : Color.white.opacity(0.95))
                    .frame(width: 14, height: 14)
                    .shadow(color: .black.opacity(0.22), radius: 1.5, x: 0, y: 0.8)
                    .offset(x: knobOffset)
            )
    }

    private func ruleCard(title: String, subtitle: String, isOn: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(bodyFont(12.5, weight: .semibold))
                    .foregroundColor(primaryText)
                Text(subtitle)
                    .font(bodyFont(11))
                    .foregroundColor(secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            toggleView(isOn: isOn)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(wellFill))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(wellBorder, lineWidth: 1))
    }

    private var rulesContent: some View {
        VStack(spacing: 8) {
            ruleCard(
                title: lang == .ru ? "Эффект Джинна в Доке" : "Genie Effect in Dock",
                subtitle: lang == .ru ? "Клик по иконке активного приложения в Доке плавно сворачивает его с анимацией" : "Clicking the active app icon in Dock smoothly minimizes it with animation",
                isOn: true
            )
            ruleCard(
                title: lang == .ru ? "Полное закрытие по крестику (⌘Q)" : "Quit on Close Button (⌘Q)",
                subtitle: lang == .ru ? "Завершает приложение, когда закрывается его последнее окно. Вкладки сохраняются!" : "Quits the app when its last window is closed. Tabs and sessions are preserved!",
                isOn: true
            )
            ruleCard(
                title: lang == .ru ? "Тактильный отклик (Haptic)" : "Haptic Feedback",
                subtitle: lang == .ru ? "Виброотклик трекпада Force Touch при сворачивании и закрытии окон" : "Force Touch trackpad vibration when minimizing or closing windows",
                isOn: true
            )

            VStack(alignment: .leading, spacing: 7) {
                Text(lang == .ru ? "Клик колёсиком по Доку" : "Middle-Click on Dock")
                    .font(bodyFont(12, weight: .semibold))
                    .foregroundColor(primaryText)

                let opts: [(String, String)] = lang == .ru
                    ? [("newWindow", "Новое окно"), ("quitApp", "Закрыть"), ("hideApp", "Скрыть"), ("disabled", "Выкл")]
                    : [("newWindow", "New Win"), ("quitApp", "Quit"), ("hideApp", "Hide"), ("disabled", "Off")]

                HStack(spacing: 4) {
                    ForEach(opts, id: \.0) { tag, title in
                        let sel = tag == middleClickSelected
                        Text(title)
                            .font(bodyFont(11, weight: sel ? .semibold : .medium))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                            .background {
                                if sel {
                                    RoundedRectangle(cornerRadius: 6.5, style: .continuous).fill(activeFill)
                                }
                            }
                            .foregroundColor(sel ? activeText : secondaryText)
                    }
                }
                .padding(3)
                .background(RoundedRectangle(cornerRadius: 8.5, style: .continuous).fill(Color.black.opacity(0.14)))
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(wellFill))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(wellBorder, lineWidth: 1))
        }
    }

    private var exclusionsContent: some View {
        let presets: [(String, Bool)] = [
            ("Telegram", true),
            ("Discord", true),
            ("Spotify", true),
            (lang == .ru ? "Музыка" : "Music", true)
        ]
        return VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Text(lang == .ru
                    ? "Эти приложения не завершаются (⌘Q) при закрытии окна и продолжают работать в фоне"
                    : "These apps will not quit (⌘Q) when their window is closed and will stay in background")
                    .font(bodyFont(11))
                    .foregroundColor(secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 4)

                Text(lang == .ru ? "+ Добавить приложение..." : "+ Add Application...")
                    .font(bodyFont(11.5, weight: .semibold))
                    .fixedSize()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(wellFill))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(wellBorder, lineWidth: 1))
                    .foregroundColor(primaryText)
            }

            VStack(spacing: 6) {
                ForEach(exclusions) { item in
                    HStack(spacing: 10) {
                        if let icon = item.icon {
                            Image(decorative: icon, scale: 2.0)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 24, height: 24)
                                .cornerRadius(6)
                        } else {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(item.fallbackColor)
                                .frame(width: 24, height: 24)
                                .overlay(
                                    Image(systemName: item.fallbackSymbol)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(.white)
                                )
                        }

                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.name)
                                .font(bodyFont(12, weight: .semibold))
                                .foregroundColor(primaryText)
                            Text(item.bundleId)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(secondaryText)
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(secondaryText)
                            .frame(width: 24, height: 24)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6.5)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(wellFill))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(wellBorder, lineWidth: 1))
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(lang == .ru ? "Быстрое добавление:" : "Quick Add:")
                    .font(bodyFont(11))
                    .foregroundColor(secondaryText)

                HStack(spacing: 6) {
                    ForEach(presets, id: \.0) { name, inc in
                        Text(inc ? "✓ \(name)" : "+ \(name)")
                            .font(bodyFont(11, weight: inc ? .semibold : .regular))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4.5)
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(inc ? activeFill : wellFill))
                            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(inc ? Color.clear : wellBorder, lineWidth: 1))
                            .foregroundColor(inc ? activeText : secondaryText)
                    }
                }
            }
        }
    }

    private var systemContent: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(lang == .ru ? "Версия v2.2.0 актуальна" : "Version 2.2.0 is up to date")
                        .font(bodyFont(12.5, weight: .semibold))
                        .foregroundColor(primaryText)
                    Text("SHA-256 · GitHub Releases")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(secondaryText)
                }
                Spacer()
                Text(lang == .ru ? "Проверить" : "Check")
                    .font(bodyFont(11.5, weight: .semibold))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(wellFill))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(wellBorder, lineWidth: 1))
                    .foregroundColor(primaryText)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(wellFill))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(wellBorder, lineWidth: 1))

            VStack(spacing: 0) {
                systemRow(title: lang == .ru ? "Запуск при входе в систему" : "Launch at Login") {
                    toggleView(isOn: true)
                }
                rowDivider
                systemRow(title: lang == .ru ? "Показывать окно при старте" : "Show Panel on Launch") {
                    toggleView(isOn: false)
                }
                rowDivider
                systemRow(title: lang == .ru ? "Проверка обновлений" : "Update Check") {
                    menuPill(lang == .ru ? "Ежедневно" : "Daily")
                }
                rowDivider
                systemRow(title: lang == .ru ? "Язык интерфейса" : "Interface Language") {
                    menuPill(lang == .ru ? "🇷🇺 Русский" : "🇺🇸 English")
                }
                rowDivider
                systemRow(title: lang == .ru ? "Диагностический журнал" : "Diagnostic Logging") {
                    HStack(spacing: 10) {
                        Text(lang == .ru ? "Папка логов" : "Open Logs")
                            .font(bodyFont(11))
                            .foregroundColor(secondaryText)
                            .underline()
                        toggleView(isOn: false)
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(wellFill))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(wellBorder, lineWidth: 1))
        }
    }

    private func menuPill(_ label: String) -> some View {
        HStack(spacing: 5) {
            Text(label)
                .font(bodyFont(11.5, weight: .medium))
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundColor(secondaryText)
        }
        .foregroundColor(primaryText)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6.5, style: .continuous).fill(Color.white.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 6.5, style: .continuous).stroke(wellBorder, lineWidth: 0.8))
    }

    private func systemRow<Trailing: View>(title: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack {
            Text(title)
                .font(bodyFont(12, weight: .medium))
                .foregroundColor(primaryText)
                .lineLimit(1)
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 8.5)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(hairline)
            .frame(height: 1)
            .padding(.leading, 13)
    }

    private var footerBar: some View {
        VStack(spacing: 9) {
            Rectangle()
                .fill(hairline)
                .frame(height: 1)

            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(axDot)
                        .frame(width: 6.5, height: 6.5)
                    Text(lang == .ru ? "AX активен" : "AX Active")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(secondaryText)
                }
                Spacer()
                Text(lang == .ru ? "Завершить (⌘Q)" : "Quit (⌘Q)")
                    .font(bodyFont(11.5, weight: .medium))
                    .foregroundColor(secondaryText)
            }
        }
    }
}

// MARK: - Framed Single & Hero Showcase Compositions

struct SingleTabScreenshotCanvas: View {
    let lang: ShowcaseLang
    let tab: ShowcaseTab
    let exclusions: [ExcludedMockApp]

    var body: some View {
        ZStack {
            AmbientWallpaperView(size: CGSize(width: 530, height: 500))
            DockFlowPanelMockView(
                lang: lang,
                tab: tab,
                exclusions: exclusions,
                middleClickSelected: "newWindow"
            )
            .padding(36)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

struct HeroShowcaseCanvas: View {
    let lang: ShowcaseLang
    let exclusions: [ExcludedMockApp]

    var body: some View {
        ZStack {
            AmbientWallpaperView(size: CGSize(width: 1460, height: 590))

            VStack(spacing: 18) {
                HStack(alignment: .top, spacing: 22) {
                    DockFlowPanelMockView(lang: lang, tab: .rules, exclusions: exclusions, middleClickSelected: "newWindow")
                    DockFlowPanelMockView(lang: lang, tab: .exclusions, exclusions: exclusions, middleClickSelected: "newWindow")
                    DockFlowPanelMockView(lang: lang, tab: .system, exclusions: exclusions, middleClickSelected: "newWindow")
                }
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 34)
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

// MARK: - PNG Writer

@MainActor
func savePNG<V: View>(_ view: V, scale: CGFloat, to path: String) {
    let renderer = ImageRenderer(content: view)
    renderer.scale = scale
    renderer.proposedSize = .unspecified
    guard let rawImage = renderer.cgImage else {
        print("Failed to render \(path)")
        return
    }
    // Flatten into 8-bit sRGB PNG for consistent brightness and lightweight GitHub delivery
    let w = rawImage.width
    let h = rawImage.height
    guard let srgb = CGColorSpace(name: CGColorSpace.sRGB),
          let ctx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: srgb,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          ) else { return }
    ctx.draw(rawImage, in: CGRect(x: 0, y: 0, width: w, height: h))
    guard let srgbImage = ctx.makeImage() else { return }
    let url = URL(fileURLWithPath: path)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        print("Failed to create PNG dest \(path)")
        return
    }
    CGImageDestinationAddImage(dest, srgbImage, nil)
    if CGImageDestinationFinalize(dest) {
        let sz = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
        print("Saved \(path) (\(w)x\(h), \(String(format: "%.2f MB", Double(sz)/1048576.0)))")
    } else {
        print("Failed finalize \(path)")
    }
}

_ = NSApplication.shared
MainActor.assumeIsolated {
    let outDir = "/Users/minosssh1./.gemini/antigravity/scratch/DockMinimizer/assets/screenshots"
    try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

    let ruExcl = IconLoader.sampleExclusions(lang: .ru)
    let enExcl = IconLoader.sampleExclusions(lang: .en)

    // Hero Showcase banners (2.2x scale = ~3212x1285 crisp Retina banner under GitHub 5MB asset limit)
    savePNG(HeroShowcaseCanvas(lang: .ru, exclusions: ruExcl), scale: 2.2, to: "\(outDir)/showcase_ru.png")
    savePNG(HeroShowcaseCanvas(lang: .en, exclusions: enExcl), scale: 2.2, to: "\(outDir)/showcase_en.png")

    // Individual 3x Retina tab screenshots
    savePNG(SingleTabScreenshotCanvas(lang: .ru, tab: .rules, exclusions: ruExcl), scale: 3.0, to: "\(outDir)/tab_rules_ru.png")
    savePNG(SingleTabScreenshotCanvas(lang: .ru, tab: .exclusions, exclusions: ruExcl), scale: 3.0, to: "\(outDir)/tab_exclusions_ru.png")
    savePNG(SingleTabScreenshotCanvas(lang: .ru, tab: .system, exclusions: ruExcl), scale: 3.0, to: "\(outDir)/tab_system_ru.png")

    savePNG(SingleTabScreenshotCanvas(lang: .en, tab: .rules, exclusions: enExcl), scale: 3.0, to: "\(outDir)/tab_rules_en.png")
    savePNG(SingleTabScreenshotCanvas(lang: .en, tab: .exclusions, exclusions: enExcl), scale: 3.0, to: "\(outDir)/tab_exclusions_en.png")
    savePNG(SingleTabScreenshotCanvas(lang: .en, tab: .system, exclusions: enExcl), scale: 3.0, to: "\(outDir)/tab_system_en.png")
}
