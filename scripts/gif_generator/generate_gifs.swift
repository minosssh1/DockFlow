import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

enum Language {
    case ru
    case en
}

// MARK: - Math & Easing Helpers

func clamp(_ v: CGFloat, _ lo: CGFloat = 0, _ hi: CGFloat = 1) -> CGFloat {
    min(max(v, lo), hi)
}

func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
    a + (b - a) * t
}

func easeInOutCubic(_ t: CGFloat) -> CGFloat {
    let x = clamp(t)
    return x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
}

func easeOutCubic(_ t: CGFloat) -> CGFloat {
    let x = clamp(t)
    return 1 - pow(1 - x, 3)
}

func easeOutExpo(_ t: CGFloat) -> CGFloat {
    let x = clamp(t)
    return x >= 1 ? 1 : 1 - pow(2, -10 * x)
}

func easeOutBack(_ t: CGFloat) -> CGFloat {
    let x = clamp(t)
    let c1: CGFloat = 1.70158
    let c3 = c1 + 1
    return 1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2)
}

func springPop(_ t: CGFloat) -> CGFloat {
    let x = clamp(t)
    if x == 0 || x == 1 { return x }
    return 1 - exp(-7.5 * x) * cos(x * 11.0)
}

// MARK: - Shared 8-bit sRGB Helpers & Real App Icons

@MainActor
enum AssetsStore {
    static var cachedIcons: [String: CGImage] = [:]

    static func srgbImage(width: Int, height: Int, draw: (CGContext) -> Void) -> CGImage {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        draw(ctx)
        return ctx.makeImage()!
    }

    static func appIcon(key: String, paths: [String]) -> CGImage? {
        if let hit = cachedIcons[key] { return hit }
        for p in paths where FileManager.default.fileExists(atPath: p) {
            let icon = NSWorkspace.shared.icon(forFile: p)
            let img = srgbImage(width: 128, height: 128) { ctx in
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
                icon.draw(in: NSRect(x: 0, y: 0, width: 128, height: 128), from: .zero, operation: .sourceOver, fraction: 1.0)
                NSGraphicsContext.restoreGraphicsState()
            }
            cachedIcons[key] = img
            return img
        }
        return nil
    }

    static func renderSwiftUI<V: View>(_ view: V, scale: CGFloat) -> CGImage {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        renderer.proposedSize = .unspecified
        let raw = renderer.cgImage!
        return srgbImage(width: raw.width, height: raw.height) { ctx in
            ctx.draw(raw, in: CGRect(x: 0, y: 0, width: raw.width, height: raw.height))
        }
    }
}

// MARK: - CoreGraphics Drawing Primitives (3x Retina -> 3840x2160 4K)

struct Palette {
    static let bgTop = NSColor(red: 0.14, green: 0.05, blue: 0.14, alpha: 1)
    static let bgBot = NSColor(red: 0.05, green: 0.04, blue: 0.08, alpha: 1)
    static let glassFill = NSColor(red: 0.25, green: 0.12, blue: 0.23, alpha: 0.72)
    static let glassDark = NSColor(red: 0.09, green: 0.07, blue: 0.12, alpha: 0.78)
    static let wellFill = NSColor(white: 1.0, alpha: 0.085)
    static let border = NSColor(white: 1.0, alpha: 0.16)
    static let activePill = NSColor(white: 0.94, alpha: 1.0)
    static let activeText = NSColor(white: 0.06, alpha: 1.0)
    static let primaryText = NSColor(white: 0.95, alpha: 1.0)
    static let secondaryText = NSColor(white: 1.0, alpha: 0.62)
    static let greenDot = NSColor(red: 74 / 255, green: 222 / 255, blue: 128 / 255, alpha: 0.92)
    static let coralDot = NSColor(red: 1.0, green: 0.42, blue: 0.44, alpha: 0.95)
}

@MainActor
enum Draw {
    static func drawFrostedBackground(ctx: CGContext, width: CGFloat, height: CGFloat) {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        // Clean deep obsidian-graphite base so GIF palette retains full RGB fidelity for icons & UI
        let baseGrad = CGGradient(
            colorsSpace: cs,
            colors: [
                NSColor(red: 0.11, green: 0.06, blue: 0.12, alpha: 1).cgColor,
                NSColor(red: 0.07, green: 0.05, blue: 0.09, alpha: 1).cgColor,
                NSColor(red: 0.04, green: 0.04, blue: 0.06, alpha: 1).cgColor
            ] as CFArray,
            locations: [0.0, 0.55, 1.0]
        )!
        ctx.drawLinearGradient(baseGrad, start: CGPoint(x: 0, y: height), end: CGPoint(x: width, y: 0), options: [])

        // Gentle soft rose/plum ambient glow (startRadius 0 avoids un-drawn center circle)
        let rose = CGGradient(
            colorsSpace: cs,
            colors: [
                NSColor(red: 0.78, green: 0.22, blue: 0.52, alpha: 0.24).cgColor,
                NSColor(red: 0.55, green: 0.16, blue: 0.40, alpha: 0.08).cgColor,
                NSColor(red: 0.55, green: 0.16, blue: 0.40, alpha: 0.0).cgColor
            ] as CFArray,
            locations: [0.0, 0.55, 1.0]
        )!
        ctx.drawRadialGradient(rose, startCenter: CGPoint(x: width * 0.18, y: height * 0.80), startRadius: 0, endCenter: CGPoint(x: width * 0.18, y: height * 0.80), endRadius: width * 0.55, options: [.drawsAfterEndLocation])

        let indigo = CGGradient(
            colorsSpace: cs,
            colors: [
                NSColor(red: 0.32, green: 0.22, blue: 0.56, alpha: 0.20).cgColor,
                NSColor(red: 0.20, green: 0.14, blue: 0.36, alpha: 0.0).cgColor
            ] as CFArray,
            locations: [0.0, 1.0]
        )!
        ctx.drawRadialGradient(indigo, startCenter: CGPoint(x: width * 0.84, y: height * 0.20), startRadius: 0, endCenter: CGPoint(x: width * 0.84, y: height * 0.20), endRadius: width * 0.50, options: [.drawsAfterEndLocation])
    }

    static func drawText(ctx: CGContext, _ text: String, at point: CGPoint, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = Palette.primaryText, mono: Bool = false, centerX: Bool = false, centerY: Bool = false) {
        let font = mono
            ? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
            : (NSFont(name: "Avenir Next", size: size).flatMap { NSFontManager.shared.convert($0, toHaveTrait: weight >= .semibold ? .boldFontMask : []) } ?? NSFont.systemFont(ofSize: size, weight: weight))
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let astr = NSAttributedString(string: text, attributes: attrs)
        let sz = astr.size()
        let x = centerX ? point.x - sz.width / 2 : point.x
        let y = centerY ? point.y - sz.height / 2 : point.y
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        astr.draw(at: CGPoint(x: x, y: y))
        NSGraphicsContext.restoreGraphicsState()
    }

    static func drawHeader(ctx: CGContext, width: CGFloat, topY: CGFloat, subtitle: String, pill: String) {
        // Brand pill + title aligned cleanly with DockFlow v2.2.0
        drawText(ctx: ctx, "DockFlow", at: CGPoint(x: width / 2 - 42, y: topY - 26), size: 28, weight: .bold, color: Palette.primaryText, centerX: true, centerY: true)

        let vRect = CGRect(x: width / 2 + 28, y: topY - 38, width: 68, height: 24)
        let vPath = CGPath(roundedRect: vRect, cornerWidth: 12, cornerHeight: 12, transform: nil)
        ctx.saveGState()
        ctx.setFillColor(Palette.activePill.cgColor)
        ctx.addPath(vPath)
        ctx.fillPath()
        ctx.restoreGState()
        drawText(ctx: ctx, "v2.2.0", at: CGPoint(x: vRect.midX, y: vRect.midY), size: 12, weight: .bold, color: Palette.activeText, mono: true, centerX: true, centerY: true)

        drawText(ctx: ctx, subtitle, at: CGPoint(x: width / 2, y: topY - 60), size: 15, weight: .medium, color: Palette.secondaryText, centerX: true, centerY: true)
    }

    static func drawGlassCard(ctx: CGContext, rect: CGRect, cornerRadius: CGFloat = 20, highlightStroke: NSColor = Palette.border) {
        let path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 32, color: NSColor(white: 0, alpha: 0.45).cgColor)
        ctx.setFillColor(Palette.glassFill.cgColor)
        ctx.addPath(path)
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.setFillColor(NSColor(white: 0.0, alpha: 0.16).cgColor)
        ctx.addPath(path)
        ctx.fillPath()
        ctx.setStrokeColor(highlightStroke.cgColor)
        ctx.setLineWidth(1.2)
        ctx.addPath(path)
        ctx.strokePath()
        ctx.restoreGState()
    }

    static func drawAppWindowImage(title: String, appBadge: CGColor, lines: Int = 5) -> CGImage {
        let w = 840
        let h = 510
        return AssetsStore.srgbImage(width: w, height: h) { ctx in
            let rect = CGRect(x: 0, y: 0, width: w, height: h)
            let path = CGPath(roundedRect: rect, cornerWidth: 32, cornerHeight: 32, transform: nil)
            ctx.addPath(path)
            ctx.clip()

            // Frosted macOS window body
            ctx.setFillColor(NSColor(red: 0.14, green: 0.12, blue: 0.17, alpha: 0.96).cgColor)
            ctx.fill(rect)

            // Subtle titlebar
            let tbRect = CGRect(x: 0, y: h - 78, width: w, height: 78)
            ctx.setFillColor(NSColor(white: 1.0, alpha: 0.055).cgColor)
            ctx.fill(tbRect)
            ctx.setFillColor(NSColor(white: 1.0, alpha: 0.10).cgColor)
            ctx.fill(CGRect(x: 0, y: h - 79, width: w, height: 2))

            // Traffic lights
            let cy = CGFloat(h - 39)
            let cols: [NSColor] = [
                NSColor(red: 1.0, green: 0.37, blue: 0.34, alpha: 1),
                NSColor(red: 1.0, green: 0.74, blue: 0.18, alpha: 1),
                NSColor(red: 0.16, green: 0.78, blue: 0.25, alpha: 1)
            ]
            for (idx, c) in cols.enumerated() {
                let cx = CGFloat(42 + idx * 42)
                ctx.setFillColor(c.cgColor)
                ctx.fillEllipse(in: CGRect(x: cx - 13, y: cy - 13, width: 26, height: 26))
            }

            // Title text (scale 2.5x inside texture)
            drawText(ctx: ctx, title, at: CGPoint(x: CGFloat(w) / 2, y: cy), size: 28, weight: .semibold, color: NSColor(white: 0.88, alpha: 1), centerX: true, centerY: true)

            // Crisp abstract macOS UI content blocks inside window
            let sideW: CGFloat = 210
            ctx.setFillColor(NSColor(white: 1.0, alpha: 0.035).cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: sideW, height: CGFloat(h - 79)))

            // Accent pill in sidebar
            let badgePath = CGPath(roundedRect: CGRect(x: 28, y: h - 148, width: 154, height: 42), cornerWidth: 12, cornerHeight: 12, transform: nil)
            ctx.setFillColor(appBadge)
            ctx.addPath(badgePath)
            ctx.fillPath()
            for row in 0..<3 {
                let r = CGRect(x: 28, y: h - 220 - row * 52, width: 125 - (row * 16), height: 22)
                let rp = CGPath(roundedRect: r, cornerWidth: 9, cornerHeight: 9, transform: nil)
                ctx.setFillColor(NSColor(white: 1, alpha: 0.10).cgColor)
                ctx.addPath(rp)
                ctx.fillPath()
            }

            // Main pane skeleton bars
            let widths: [CGFloat] = [440, 350, 480, 290, 390]
            for row in 0..<min(lines, widths.count) {
                let y = CGFloat(h - 140 - row * 68)
                let r = CGRect(x: sideW + 46, y: y, width: widths[row], height: row == 0 ? 34 : 22)
                let rp = CGPath(roundedRect: r, cornerWidth: 10, cornerHeight: 10, transform: nil)
                ctx.setFillColor(NSColor(white: 1, alpha: row == 0 ? 0.22 : 0.11).cgColor)
                ctx.addPath(rp)
                ctx.fillPath()
            }

            // Border
            ctx.setStrokeColor(NSColor(white: 1, alpha: 0.22).cgColor)
            ctx.setLineWidth(3)
            ctx.addPath(path)
            ctx.strokePath()
        }
    }

    static func drawGenieWarpedWindow(
        ctx: CGContext,
        windowImage: CGImage,
        normalRect: CGRect,
        targetIconPoint: CGPoint,
        progress: CGFloat // 0 = full window, 1 = completely tucked into Dock icon
    ) {
        let p = clamp(progress)
        if p >= 0.99 { return }

        if p <= 0.001 {
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 24, color: NSColor(white: 0, alpha: 0.45).cgColor)
            ctx.draw(windowImage, in: normalRect)
            ctx.restoreGState()
            return
        }

        // Curved horizontal slice Genie deformation
        let strips = 30
        let imgH = CGFloat(windowImage.height)
        let imgW = CGFloat(windowImage.width)
        let stripSrcH = imgH / CGFloat(strips)

        let topShiftP = easeInOutCubic(clamp((p - 0.18) / 0.82))
        let botShiftP = easeOutCubic(clamp(p / 0.72))

        let topY = lerp(normalRect.maxY, targetIconPoint.y + 8, topShiftP)
        let botY = lerp(normalRect.minY, targetIconPoint.y, botShiftP)
        let curTotalH = max(4, topY - botY)

        ctx.saveGState()
        ctx.setAlpha(clamp(1.0 - max(0, p - 0.75) / 0.25))

        for s in 0..<strips {
            // s=0 bottom, s=strips-1 top
            let frac0 = CGFloat(s) / CGFloat(strips)
            let frac1 = CGFloat(s + 1) / CGFloat(strips)
            let midFrac = (frac0 + frac1) * 0.5

            // Bottom shrinks into narrow funnel first while top narrows slightly behind it
            let funnelDelay = midFrac * 0.42
            let localSqueeze = easeInOutCubic(clamp((p - funnelDelay * 0.55) / (1.0 - funnelDelay * 0.55)))
            let curvedWidthFactor = lerp(1.0, 0.08 + 0.16 * midFrac, localSqueeze)
            let stripW = max(6, normalRect.width * curvedWidthFactor)

            let xShift = lerp(normalRect.midX, targetIconPoint.x, easeInOutCubic(clamp(localSqueeze * (1.15 - 0.25 * midFrac))))
            let dstY0 = botY + curTotalH * frac0
            let dstH = curTotalH * (frac1 - frac0) + 0.8

            let cropY = CGFloat(strips - 1 - s) * stripSrcH // CGImage cropping uses top-left origin
            if let slice = windowImage.cropping(to: CGRect(x: 0, y: cropY, width: imgW, height: stripSrcH)) {
                ctx.draw(slice, in: CGRect(x: xShift - stripW / 2, y: dstY0, width: stripW, height: dstH))
            }
        }
        ctx.restoreGState()
    }

    static func drawRealDock(
        ctx: CGContext,
        center: CGPoint,
        width: CGFloat,
        icons: [(String, CGImage?, NSColor)],
        runningIndices: [Int],
        bounceIndex: Int? = nil,
        bounceOffset: CGFloat = 0,
        activeHighlightIndex: Int? = nil,
        labelIndex: Int? = nil,
        labelText: String? = nil
    ) {
        let dockH: CGFloat = 68
        let dockRect = CGRect(x: center.x - width / 2, y: center.y - dockH / 2, width: width, height: dockH)
        let dockPath = CGPath(roundedRect: dockRect, cornerWidth: 20, cornerHeight: 20, transform: nil)

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 20, color: NSColor(white: 0, alpha: 0.48).cgColor)
        ctx.setFillColor(NSColor(red: 0.14, green: 0.11, blue: 0.16, alpha: 0.88).cgColor)
        ctx.addPath(dockPath)
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.setStrokeColor(NSColor(white: 1, alpha: 0.22).cgColor)
        ctx.setLineWidth(1)
        ctx.addPath(dockPath)
        ctx.strokePath()
        ctx.restoreGState()

        let count = icons.count
        let sidePad: CGFloat = 18
        let usableW = width - sidePad * 2
        let slotW = usableW / CGFloat(count)
        let iconSz: CGFloat = 46

        for (i, item) in icons.enumerated() {
            let cx = dockRect.minX + sidePad + slotW * (CGFloat(i) + 0.5)
            let isBouncing = (bounceIndex == i)
            let cy = center.y + 3 + (isBouncing ? bounceOffset : 0)
            let iconRect = CGRect(x: cx - iconSz / 2, y: cy - iconSz / 2, width: iconSz, height: iconSz)

            if activeHighlightIndex == i {
                let glowRect = iconRect.insetBy(dx: -4, dy: -4)
                let gp = CGPath(roundedRect: glowRect, cornerWidth: 11, cornerHeight: 11, transform: nil)
                ctx.saveGState()
                ctx.setStrokeColor(NSColor(white: 1, alpha: 0.45).cgColor)
                ctx.setLineWidth(1.5)
                ctx.addPath(gp)
                ctx.strokePath()
                ctx.restoreGState()
            }

            if let cgImg = item.1 {
                ctx.draw(cgImg, in: iconRect)
            } else {
                drawCrispVectorIcon(ctx: ctx, tag: item.0, rect: iconRect)
            }

            if runningIndices.contains(i) {
                ctx.setFillColor(NSColor.white.cgColor)
                ctx.fillEllipse(in: CGRect(x: cx - 2.3, y: dockRect.minY + 4.5, width: 4.6, height: 4.6))
            }

            if labelIndex == i, let badge = labelText {
                let bw: CGFloat = 138
                let bh: CGFloat = 22
                let bRect = CGRect(x: cx - bw / 2, y: dockRect.maxY + 8, width: bw, height: bh)
                let bp = CGPath(roundedRect: bRect, cornerWidth: 8, cornerHeight: 8, transform: nil)
                ctx.saveGState()
                ctx.setFillColor(Palette.activePill.cgColor)
                ctx.addPath(bp)
                ctx.fillPath()
                ctx.restoreGState()
                drawText(ctx: ctx, badge, at: CGPoint(x: bRect.midX, y: bRect.midY), size: 10.5, weight: .bold, color: Palette.activeText, centerX: true, centerY: true)
            }
        }
    }

    static func drawCrispVectorIcon(ctx: CGContext, tag: String, rect: CGRect) {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ip = CGPath(roundedRect: rect, cornerWidth: 10.5, cornerHeight: 10.5, transform: nil)
        ctx.saveGState()
        ctx.addPath(ip)
        ctx.clip()

        let colors: [CGColor]
        switch tag {
        case "Finder":
            colors = [NSColor(red: 0.28, green: 0.68, blue: 0.99, alpha: 1).cgColor, NSColor(red: 0.12, green: 0.44, blue: 0.92, alpha: 1).cgColor]
        case "Safari":
            colors = [NSColor(red: 0.22, green: 0.72, blue: 0.98, alpha: 1).cgColor, NSColor(red: 0.12, green: 0.42, blue: 0.88, alpha: 1).cgColor]
        case "Notes":
            colors = [NSColor(red: 0.99, green: 0.82, blue: 0.20, alpha: 1).cgColor, NSColor(red: 0.94, green: 0.65, blue: 0.12, alpha: 1).cgColor]
        case "Telegram":
            colors = [NSColor(red: 0.22, green: 0.68, blue: 0.96, alpha: 1).cgColor, NSColor(red: 0.12, green: 0.50, blue: 0.86, alpha: 1).cgColor]
        case "DockFlow":
            colors = [NSColor(red: 0.82, green: 0.28, blue: 0.62, alpha: 1).cgColor, NSColor(red: 0.36, green: 0.24, blue: 0.74, alpha: 1).cgColor]
        default: // Music
            colors = [NSColor(red: 0.98, green: 0.24, blue: 0.42, alpha: 1).cgColor, NSColor(red: 0.82, green: 0.14, blue: 0.30, alpha: 1).cgColor]
        }
        let grad = CGGradient(colorsSpace: cs, colors: colors as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(grad, start: CGPoint(x: rect.minX, y: rect.maxY), end: CGPoint(x: rect.maxX, y: rect.minY), options: [])

        if tag == "Notes" {
            // Crisp top yellow header + ruled cream pad
            ctx.setFillColor(NSColor(white: 0.98, alpha: 1).cgColor)
            ctx.fill(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.72))
            ctx.setFillColor(NSColor(white: 0.78, alpha: 1).cgColor)
            for r in 0..<3 {
                ctx.fill(CGRect(x: rect.minX + 8, y: rect.minY + 9 + CGFloat(r) * 7.5, width: rect.width - 16, height: 1.4))
            }
        } else if tag == "Safari" {
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(2.0)
            ctx.strokeEllipse(in: rect.insetBy(dx: 8, dy: 8))
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fillEllipse(in: CGRect(x: rect.midX - 2.5, y: rect.midY - 2.5, width: 5, height: 5))
        } else if tag == "Finder" {
            let smile = CGMutablePath()
            smile.addArc(center: CGPoint(x: rect.midX, y: rect.midY + 2), radius: 8.5, startAngle: 1.15 * .pi, endAngle: 1.85 * .pi, clockwise: false)
            ctx.setStrokeColor(NSColor.white.cgColor); ctx.setLineWidth(2.0)
            ctx.addPath(smile); ctx.strokePath()
        } else if tag == "Telegram" {
            let tri = CGMutablePath()
            tri.move(to: CGPoint(x: rect.midX + 9, y: rect.midY + 6))
            tri.addLine(to: CGPoint(x: rect.midX - 9, y: rect.midY))
            tri.addLine(to: CGPoint(x: rect.midX - 1, y: rect.midY - 8))
            tri.closeSubpath()
            ctx.setFillColor(NSColor.white.cgColor); ctx.addPath(tri); ctx.fillPath()
        } else if tag == "DockFlow" {
            let dp = CGPath(roundedRect: rect.insetBy(dx: 10, dy: 12), cornerWidth: 3, cornerHeight: 3, transform: nil)
            ctx.setStrokeColor(NSColor.white.cgColor); ctx.setLineWidth(2.0)
            ctx.addPath(dp); ctx.strokePath()
        } else {
            drawText(ctx: ctx, "♫", at: CGPoint(x: rect.midX, y: rect.midY), size: 19, weight: .bold, color: .white, centerX: true, centerY: true)
        }
        ctx.restoreGState()
    }

    static func drawCursor(ctx: CGContext, at: CGPoint, clicking: Bool, rippleProgress: CGFloat = 0) {
        ctx.saveGState()
        if clicking || rippleProgress > 0 {
            let rp = clicking ? 0.35 : rippleProgress
            let rad = lerp(8, 22, rp)
            ctx.setStrokeColor(NSColor(white: 1.0, alpha: clamp(0.85 * (1 - rp))).cgColor)
            ctx.setLineWidth(2.2)
            ctx.strokeEllipse(in: CGRect(x: at.x - rad, y: at.y - rad, width: rad * 2, height: rad * 2))
        }

        ctx.setShadow(offset: CGSize(width: 1, height: -2), blur: 6, color: NSColor(white: 0, alpha: 0.65).cgColor)
        let p = CGMutablePath()
        p.move(to: at)
        p.addLine(to: CGPoint(x: at.x + 13, y: at.y - 13))
        p.addLine(to: CGPoint(x: at.x + 6, y: at.y - 13))
        p.addLine(to: CGPoint(x: at.x + 9.5, y: at.y - 20.5))
        p.addLine(to: CGPoint(x: at.x + 5.5, y: at.y - 22.0))
        p.addLine(to: CGPoint(x: at.x + 2, y: at.y - 14.5))
        p.addLine(to: CGPoint(x: at.x, y: at.y - 18))
        p.closeSubpath()

        ctx.setFillColor(NSColor.black.cgColor)
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(1.6)
        ctx.addPath(p)
        ctx.drawPath(using: .fillStroke)
        ctx.restoreGState()
    }
}

// MARK: - SwiftUI Embedded UI Frame Renderer for GIF 3 (UI Flow 4K - Zero Overlap, Sliding Pills, Spring Toggle)

struct TabFrameMetrics {
    let widths: [CGFloat]
    let centers: [CGFloat]
}

struct UIPanelSnapshotView: View {
    let lang: Language
    let targetTab: Int
    let tabPillPosition: CGFloat // continuously animated 0.0 -> 1.0 -> 2.0 -> 0.0
    let toggleProgress: CGFloat  // continuously animated 0.0 (off) -> 1.0 (on)
    let midPillPosition: CGFloat // continuously animated 0.0 (New Win) -> 1.0 (Quit)
    let panelHeight: CGFloat
    let activeTabLayerOpacity: (tab0: Double, tab1: Double, tab2: Double)
    let activeTabYOffset: (tab0: CGFloat, tab1: CGFloat, tab2: CGFloat)
    let icons: [(String, CGImage?)]

    private let activeFill = Color(white: 0.94)
    private let activeText = Color(white: 0.06)
    private let primaryText = Color.white.opacity(0.94)
    private let secondaryText = Color.white.opacity(0.60)
    private let wellFill = Color.white.opacity(0.085)
    private let wellBorder = Color.white.opacity(0.14)
    private let hairline = Color.white.opacity(0.14)

    private func bodyFont(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Avenir Next", size: size).weight(weight)
    }

    private func tabRowText(t0: String, t1: String, t2: String, w0: CGFloat, w1: CGFloat, w2: CGFloat, spacing: CGFloat, pad: CGFloat, color: Color) -> some View {
        HStack(spacing: spacing) {
            Text(t0)
                .font(bodyFont(11.5, weight: targetTab == 0 ? .semibold : .medium))
                .frame(width: w0, height: 24)
            Text(t1)
                .font(bodyFont(11.5, weight: targetTab == 1 ? .semibold : .medium))
                .frame(width: w1, height: 24)
            Text(t2)
                .font(bodyFont(11.5, weight: targetTab == 2 ? .semibold : .medium))
                .frame(width: w2, height: 24)
        }
        .foregroundColor(color)
        .padding(pad)
    }

    var body: some View {
        let t0 = lang == .ru ? "Правила" : "Rules"
        let t1 = lang == .ru ? "Исключения (4)" : "Exclusions (4)"
        let t2 = lang == .ru ? "Система" : "System"
        let w0: CGFloat = lang == .ru ? 68 : 54
        let w1: CGFloat = lang == .ru ? 108 : 102
        let w2: CGFloat = lang == .ru ? 66 : 62
        let spacing: CGFloat = 2
        let pad: CGFloat = 3

        let p = tabPillPosition
        let pillWidth: CGFloat = {
            if p <= 1.0 { return lerp(w0, w1, p) }
            return lerp(w1, w2, p - 1.0)
        }()
        let pillX: CGFloat = {
            let x0: CGFloat = pad
            let x1: CGFloat = pad + w0 + spacing
            let x2: CGFloat = pad + w0 + spacing + w1 + spacing
            if p <= 1.0 { return lerp(x0, x1, p) }
            return lerp(x1, x2, p - 1.0)
        }()

        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("DockFlow").font(bodyFont(13.5, weight: .bold)).foregroundColor(primaryText)
                    Text("v2.0").font(.system(size: 11, design: .monospaced)).foregroundColor(secondaryText)
                }
                Spacer()

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                        .fill(activeFill)
                        .frame(width: pillWidth, height: 24)
                        .offset(x: pillX)

                    tabRowText(t0: t0, t1: t1, t2: t2, w0: w0, w1: w1, w2: w2, spacing: spacing, pad: pad, color: secondaryText)

                    tabRowText(t0: t0, t1: t1, t2: t2, w0: w0, w1: w1, w2: w2, spacing: spacing, pad: pad, color: activeText)
                        .mask(
                            HStack(spacing: 0) {
                                RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                                    .frame(width: pillWidth, height: 24)
                                    .offset(x: pillX)
                                Spacer(minLength: 0)
                            }
                        )
                }
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(wellFill))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(wellBorder, lineWidth: 1))
            }
            .padding(.horizontal, 14).padding(.vertical, 11)

            Rectangle().fill(hairline).frame(height: 1)

            VStack(spacing: 0) {
                ZStack(alignment: .top) {
                    if activeTabLayerOpacity.tab0 > 0.01 {
                        rulesTab
                            .opacity(activeTabLayerOpacity.tab0)
                            .offset(y: activeTabYOffset.tab0)
                    }
                    if activeTabLayerOpacity.tab1 > 0.01 {
                        exclusionsTab
                            .opacity(activeTabLayerOpacity.tab1)
                            .offset(y: activeTabYOffset.tab1)
                    }
                    if activeTabLayerOpacity.tab2 > 0.01 {
                        systemTab
                            .opacity(activeTabLayerOpacity.tab2)
                            .offset(y: activeTabYOffset.tab2)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .clipped()
                .padding(.bottom, 10)

                VStack(spacing: 9) {
                    Rectangle().fill(hairline).frame(height: 1)
                    HStack {
                        HStack(spacing: 6) {
                            Circle().fill(Color(red: 74/255, green: 222/255, blue: 128/255)).frame(width: 6.5, height: 6.5)
                            Text(lang == .ru ? "AX активен" : "AX Active").font(.system(size: 11, design: .monospaced)).foregroundColor(secondaryText)
                        }
                        Spacer()
                        Text(lang == .ru ? "Завершить (⌘Q)" : "Quit (⌘Q)").font(bodyFont(11.5, weight: .medium)).foregroundColor(secondaryText)
                    }
                }
            }
            .padding(14)
        }
        .frame(width: 446, height: panelHeight, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 0.19, green: 0.10, blue: 0.18))
        )
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.24), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func toggleView(_ progress: CGFloat) -> some View {
        let p = clamp(progress)
        // Pill-stretch physics at mid-transition (14 -> 18.5 -> 14)
        let stretch = sin(p * .pi)
        let knobW: CGFloat = 14.0 + 4.5 * stretch
        let travel: CGFloat = 32.0 - 4.0 - knobW
        let knobX: CGFloat = lerp(-(travel / 2.0), (travel / 2.0), p)
        let trackR = lerp(0.28, 0.94, p)
        let trackG = lerp(0.20, 0.94, p)
        let trackB = lerp(0.27, 0.94, p)
        let knobShade = lerp(0.95, 0.06, p)
        return Capsule(style: .continuous)
            .fill(Color(red: trackR, green: trackG, blue: trackB))
            .frame(width: 32, height: 18)
            .overlay(
                Capsule(style: .continuous)
                    .fill(Color(white: knobShade))
                    .frame(width: knobW, height: 14)
                    .offset(x: knobX)
            )
    }

    private func ruleCard(_ title: String, _ sub: String, _ toggleP: CGFloat) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(bodyFont(12.5, weight: .semibold)).foregroundColor(primaryText)
                Text(sub).font(bodyFont(11)).foregroundColor(secondaryText).lineLimit(2)
            }
            Spacer(minLength: 8)
            toggleView(toggleP)
        }
        .padding(.horizontal, 13).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(wellFill))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(wellBorder, lineWidth: 1))
    }

    private var rulesTab: some View {
        let segW: CGFloat = (392.0 - 12.0) / 4.0 // inner container width = 446 - 28 - 26 = 392, minus spacing/padding
        let segGap: CGFloat = 4.0
        let pillOffsetX: CGFloat = 3.0 + midPillPosition * (segW + segGap)

        return VStack(spacing: 8) {
            ruleCard(
                lang == .ru ? "Эффект Джинна в Доке" : "Genie Effect in Dock",
                lang == .ru ? "Клик по иконке активного приложения в Доке плавно сворачивает его с анимацией" : "Clicking the active app icon in Dock smoothly minimizes it with animation",
                toggleProgress
            )
            ruleCard(
                lang == .ru ? "Полное закрытие по крестику (⌘Q)" : "Quit on Close Button (⌘Q)",
                lang == .ru ? "Завершает приложение, когда закрывается его последнее окно. Вкладки сохраняются!" : "Quits the app when its last window is closed. Tabs and sessions are preserved!",
                1.0
            )
            ruleCard(
                lang == .ru ? "Тактильный отклик (Haptic)" : "Haptic Feedback",
                lang == .ru ? "Виброотклик трекпада Force Touch при сворачивании и закрытии окон" : "Force Touch trackpad vibration when minimizing or closing windows",
                1.0
            )
            VStack(alignment: .leading, spacing: 7) {
                Text(lang == .ru ? "Клик колёсиком по Доку" : "Middle-Click on Dock").font(bodyFont(12, weight: .semibold)).foregroundColor(primaryText)
                let opts = lang == .ru ? ["Новое окно", "Закрыть", "Скрыть", "Выкл"] : ["New Win", "Quit", "Hide", "Off"]

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                        .fill(activeFill)
                        .frame(width: segW, height: 24)
                        .offset(x: pillOffsetX)

                    HStack(spacing: segGap) {
                        ForEach(Array(opts.enumerated()), id: \.offset) { _, t in
                            Text(t)
                                .font(bodyFont(11, weight: .medium))
                                .frame(width: segW, height: 24)
                        }
                    }
                    .foregroundColor(secondaryText)
                    .padding(3)

                    HStack(spacing: segGap) {
                        ForEach(Array(opts.enumerated()), id: \.offset) { _, t in
                            Text(t)
                                .font(bodyFont(11, weight: .semibold))
                                .frame(width: segW, height: 24)
                        }
                    }
                    .foregroundColor(activeText)
                    .padding(3)
                    .mask(
                        HStack(spacing: 0) {
                            RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                                .frame(width: segW, height: 24)
                                .offset(x: pillOffsetX)
                            Spacer(minLength: 0)
                        }
                    )
                }
                .background(RoundedRectangle(cornerRadius: 8.5, style: .continuous).fill(Color.black.opacity(0.14)))
            }
            .padding(.horizontal, 13).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(wellFill))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(wellBorder, lineWidth: 1))
        }
    }

    private var exclusionsTab: some View {
        let items: [(String, String, Color)] = [
            ("Telegram", "ru.keepcoder.Telegram", .blue),
            ("Discord", "com.hnc.Discord", .indigo),
            ("Spotify", "com.spotify.client", .green),
            (lang == .ru ? "Музыка" : "Music", "com.apple.Music", .pink)
        ]
        return VStack(spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                HStack(spacing: 10) {
                    if idx < icons.count, let img = icons[idx].1 {
                        Image(decorative: img, scale: 2.0).resizable().frame(width: 24, height: 24).cornerRadius(6)
                    } else {
                        RoundedRectangle(cornerRadius: 6).fill(item.2).frame(width: 24, height: 24)
                            .overlay(
                                Image(systemName: "dot.radiowaves.left.and.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.white)
                            )
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.0).font(bodyFont(12, weight: .semibold)).foregroundColor(primaryText)
                        Text(item.1).font(.system(size: 10, design: .monospaced)).foregroundColor(secondaryText)
                    }
                    Spacer()
                    Image(systemName: "xmark").font(.system(size: 11)).foregroundColor(secondaryText)
                }
                .padding(.horizontal, 11).padding(.vertical, 6.5)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(wellFill))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(wellBorder, lineWidth: 1))
            }
        }
    }

    private var systemTab: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(lang == .ru ? "Версия v2.0 актуальна" : "Version 2.0 is up to date").font(bodyFont(12.5, weight: .semibold)).foregroundColor(primaryText)
                    Text("SHA-256 · GitHub Releases").font(.system(size: 10.5, design: .monospaced)).foregroundColor(secondaryText)
                }
                Spacer()
                Text(lang == .ru ? "Проверить" : "Check").font(bodyFont(11.5, weight: .semibold))
                    .padding(.horizontal, 11).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(wellFill))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(wellBorder, lineWidth: 1))
                    .foregroundColor(primaryText)
            }
            .padding(.horizontal, 13).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(wellFill))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(wellBorder, lineWidth: 1))

            VStack(spacing: 0) {
                row(lang == .ru ? "Запуск при входе в систему" : "Launch at Login", on: true)
                Rectangle().fill(hairline).frame(height: 1).padding(.leading, 13)
                row(lang == .ru ? "Показывать окно при старте" : "Show Panel on Launch", on: false)
                Rectangle().fill(hairline).frame(height: 1).padding(.leading, 13)
                row(lang == .ru ? "Диагностический журнал" : "Diagnostic Logging", on: false)
            }
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(wellFill))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(wellBorder, lineWidth: 1))
        }
    }

    private func row(_ title: String, on: Bool) -> some View {
        HStack {
            Text(title).font(bodyFont(12, weight: .medium)).foregroundColor(primaryText)
            Spacer()
            toggleView(on ? 1.0 : 0.0)
        }
        .padding(.horizontal, 13).padding(.vertical, 8.5)
    }
}

// MARK: - Generator 1: 4K Dock Minimize & Restore (3840x2160)

@MainActor
func generateDockMinimize4K(outputPath: String, lang: Language) {
    let ptW: CGFloat = 1280
    let ptH: CGFloat = 720
    let scale: CGFloat = 1.5 // 1920x1080 Full HD!
    let pxW = Int(ptW * scale)
    let pxH = Int(ptH * scale)
    let frameCount = 150
    let delay = 0.02

    let dockIcons: [(String, CGImage?, NSColor)] = [
        ("Finder", nil, .systemBlue),
        ("Safari", nil, .systemTeal),
        ("Notes", nil, .systemYellow),
        ("Telegram", nil, .systemCyan),
        ("DockFlow", nil, .systemPurple),
        ("Music", nil, .systemPink)
    ]

    let winImg = Draw.drawAppWindowImage(
        title: lang == .ru ? "Заметки — Notes" : "Notes — Application",
        appBadge: NSColor(red: 0.96, green: 0.76, blue: 0.18, alpha: 0.85).cgColor
    )

    let leftCard = CGRect(x: 42, y: 44, width: 576, height: 540)
    let rightCard = CGRect(x: ptW - 42 - 576, y: 44, width: 576, height: 540)

    // Pre-render static 4K backdrop ONCE so delta LZW keeps file size compact for GitHub
    let staticBg = AssetsStore.srgbImage(width: pxW, height: pxH) { ctx in
        ctx.scaleBy(x: scale, y: scale)
        Draw.drawFrostedBackground(ctx: ctx, width: ptW, height: ptH)
        Draw.drawHeader(
            ctx: ctx,
            width: ptW,
            topY: ptH - 28,
            subtitle: lang == .ru
                ? "Эффект Джинна: повторный клик по иконке плавно сворачивает и разворачивает окно"
                : "Genie Effect: clicking an active Dock icon smoothly minimizes and restores it",
            pill: "v2.2.0"
        )
        Draw.drawGlassCard(ctx: ctx, rect: leftCard)
        Draw.drawGlassCard(ctx: ctx, rect: rightCard)

        Draw.drawText(ctx: ctx, lang == .ru ? "КЛИК ПО ИКОНКЕ — СВЕРНУТЬ" : "CLICK ICON — MINIMIZE", at: CGPoint(x: leftCard.midX, y: leftCard.maxY - 34), size: 12.5, weight: .bold, color: Palette.secondaryText, centerX: true, centerY: true)
        Draw.drawText(ctx: ctx, lang == .ru ? "ПОВТОРНЫЙ КЛИК — РАЗВЕРНУТЬ" : "CLICK AGAIN — RESTORE", at: CGPoint(x: rightCard.midX, y: rightCard.maxY - 34), size: 12.5, weight: .bold, color: Palette.secondaryText, centerX: true, centerY: true)
    }

    let url = URL(fileURLWithPath: outputPath)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frameCount, nil)!
    CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    let fp = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay, kCGImagePropertyGIFUnclampedDelayTime: delay]] as CFDictionary

    let leftWinRect = CGRect(x: leftCard.midX - 185, y: leftCard.minY + 230, width: 370, height: 225)
    let rightWinRect = CGRect(x: rightCard.midX - 185, y: rightCard.minY + 230, width: 370, height: 225)
    let leftDockCenter = CGPoint(x: leftCard.midX, y: leftCard.minY + 80)
    let rightDockCenter = CGPoint(x: rightCard.midX, y: rightCard.minY + 80)

    // Index 2 is Notes in our 6-icon dock (width 420, sidePad 18 -> slot = 384/6 = 64 -> idx 2 center = minX + 18 + 2.5 * 64 = minX + 178 = center - 32)
    let notesIconPosL = CGPoint(x: leftDockCenter.x - 32, y: leftDockCenter.y + 3)
    let notesIconPosR = CGPoint(x: rightDockCenter.x - 32, y: rightDockCenter.y + 3)

    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let frameCtx = CGContext(data: nil, width: pxW, height: pxH, bitsPerComponent: 8, bytesPerRow: pxW * 4, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

    for f in 0..<frameCount {
        let t = CGFloat(f) / CGFloat(frameCount)
        frameCtx.saveGState()
        frameCtx.clear(CGRect(x: 0, y: 0, width: pxW, height: pxH))
        frameCtx.draw(staticBg, in: CGRect(x: 0, y: 0, width: pxW, height: pxH))
        frameCtx.scaleBy(x: scale, y: scale)

        // LEFT: Minimize
        var lProgress: CGFloat = 0
        var lCursor = CGPoint(x: leftCard.midX - 45, y: leftCard.midY + 25)
        var lClick = false
        var lRipple: CGFloat = 0
        var lBounce: CGFloat = 0

        if t < 0.24 {
            let p = easeInOutCubic(t / 0.24)
            lCursor = CGPoint(x: lerp(leftCard.midX - 45, notesIconPosL.x, p), y: lerp(leftCard.midY + 25, notesIconPosL.y, p))
        } else if t < 0.34 {
            lCursor = notesIconPosL
            lClick = (t >= 0.26 && t <= 0.32)
            lRipple = clamp((t - 0.26) / 0.08)
            lBounce = sin(clamp((t - 0.25) / 0.09) * .pi) * 7
        } else if t < 0.68 {
            lCursor = notesIconPosL
            lProgress = clamp((t - 0.34) / 0.34)
        } else {
            lCursor = notesIconPosL
            lProgress = 1.0
        }

        Draw.drawRealDock(ctx: frameCtx, center: leftDockCenter, width: 420, icons: dockIcons, runningIndices: [0, 1, 2, 3, 4], bounceIndex: 2, bounceOffset: lBounce, activeHighlightIndex: 2)
        Draw.drawGenieWarpedWindow(ctx: frameCtx, windowImage: winImg, normalRect: leftWinRect, targetIconPoint: notesIconPosL, progress: lProgress)
        Draw.drawCursor(ctx: frameCtx, at: lCursor, clicking: lClick, rippleProgress: lRipple)

        // RIGHT: Restore
        var rProgress: CGFloat = 1.0
        var rCursor = CGPoint(x: notesIconPosR.x + 45, y: notesIconPosR.y + 30)
        var rClick = false
        var rRipple: CGFloat = 0
        var rBounce: CGFloat = 0

        if t < 0.20 {
            let p = easeInOutCubic(t / 0.20)
            rCursor = CGPoint(x: lerp(notesIconPosR.x + 45, notesIconPosR.x, p), y: lerp(notesIconPosR.y + 30, notesIconPosR.y, p))
        } else if t < 0.30 {
            rCursor = notesIconPosR
            rClick = (t >= 0.22 && t <= 0.28)
            rRipple = clamp((t - 0.22) / 0.08)
            rBounce = sin(clamp((t - 0.21) / 0.09) * .pi) * 7
        } else if t < 0.64 {
            rCursor = notesIconPosR
            rProgress = 1.0 - clamp((t - 0.30) / 0.34)
        } else {
            rCursor = notesIconPosR
            rProgress = 0.0
        }

        Draw.drawRealDock(ctx: frameCtx, center: rightDockCenter, width: 420, icons: dockIcons, runningIndices: [0, 1, 2, 3, 4], bounceIndex: 2, bounceOffset: rBounce, activeHighlightIndex: 2)
        Draw.drawGenieWarpedWindow(ctx: frameCtx, windowImage: winImg, normalRect: rightWinRect, targetIconPoint: notesIconPosR, progress: rProgress)
        Draw.drawCursor(ctx: frameCtx, at: rCursor, clicking: rClick, rippleProgress: rRipple)

        frameCtx.restoreGState()
        CGImageDestinationAddImage(dest, frameCtx.makeImage()!, fp)
    }

    if CGImageDestinationFinalize(dest) {
        let sz = (try? FileManager.default.attributesOfItem(atPath: outputPath)[.size] as? Int) ?? 0
        print("Saved 4K GIF \(outputPath) (\(pxW)x\(pxH), \(String(format: "%.2f MB", Double(sz)/1048576.0)))")
    }
}

// MARK: - Generator 2: 4K Quit on Close (⌘Q) + Exclusions (3840x2160)

@MainActor
func generateQuitOnClose4K(outputPath: String, lang: Language) {
    let ptW: CGFloat = 1280
    let ptH: CGFloat = 720
    let scale: CGFloat = 1.5 // 1920x1080 Full HD!
    let pxW = Int(ptW * scale)
    let pxH = Int(ptH * scale)
    let frameCount = 150
    let delay = 0.02

    let dockIcons: [(String, CGImage?, NSColor)] = [
        ("Finder", nil, .systemBlue),
        ("Safari", nil, .systemTeal),
        ("Telegram", nil, .systemCyan),
        ("DockFlow", nil, .systemPurple),
        ("Music", nil, .systemPink)
    ]

    let safariImg = Draw.drawAppWindowImage(
        title: lang == .ru ? "Safari — Браузер" : "Safari — Browser",
        appBadge: NSColor(red: 0.22, green: 0.62, blue: 0.98, alpha: 0.85).cgColor
    )

    let leftCard = CGRect(x: 42, y: 44, width: 576, height: 540)
    let rightCard = CGRect(x: ptW - 42 - 576, y: 44, width: 576, height: 540)

    let staticBg = AssetsStore.srgbImage(width: pxW, height: pxH) { ctx in
        ctx.scaleBy(x: scale, y: scale)
        Draw.drawFrostedBackground(ctx: ctx, width: ptW, height: ptH)
        Draw.drawHeader(
            ctx: ctx,
            width: ptW,
            topY: ptH - 28,
            subtitle: lang == .ru
                ? "Красный крестик завершает приложение целиком (⌘Q), оставляя исключения в фоне"
                : "Red close button fully quits apps (⌘Q) while keeping excluded apps in background",
            pill: "v2.2.0"
        )
        Draw.drawGlassCard(ctx: ctx, rect: leftCard)
        Draw.drawGlassCard(ctx: ctx, rect: rightCard, highlightStroke: NSColor(white: 1.0, alpha: 0.28))

        Draw.drawText(ctx: ctx, lang == .ru ? "СТАНДАРТНАЯ MACOS" : "DEFAULT MACOS", at: CGPoint(x: leftCard.midX, y: leftCard.maxY - 34), size: 12.5, weight: .bold, color: Palette.coralDot, centerX: true, centerY: true)
        Draw.drawText(ctx: ctx, lang == .ru ? "С DOCKFLOW v2.2.0" : "WITH DOCKFLOW v2.2.0", at: CGPoint(x: rightCard.midX, y: rightCard.maxY - 34), size: 12.5, weight: .bold, color: Palette.greenDot, centerX: true, centerY: true)
    }

    let url = URL(fileURLWithPath: outputPath)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frameCount, nil)!
    CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    let fp = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay, kCGImagePropertyGIFUnclampedDelayTime: delay]] as CFDictionary

    let lWinRect = CGRect(x: leftCard.midX - 185, y: leftCard.minY + 228, width: 370, height: 225)
    let rWinRect = CGRect(x: rightCard.midX - 185, y: rightCard.minY + 228, width: 370, height: 225)
    let lCloseBtn = CGPoint(x: lWinRect.minX + 18.5, y: lWinRect.maxY - 17.5)
    let rCloseBtn = CGPoint(x: rWinRect.minX + 18.5, y: rWinRect.maxY - 17.5)
    let lDockCenter = CGPoint(x: leftCard.midX, y: leftCard.minY + 80)
    let rDockCenter = CGPoint(x: rightCard.midX, y: rightCard.minY + 80)

    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let frameCtx = CGContext(data: nil, width: pxW, height: pxH, bitsPerComponent: 8, bytesPerRow: pxW * 4, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

    for f in 0..<frameCount {
        let t = CGFloat(f) / CGFloat(frameCount)
        frameCtx.saveGState()
        frameCtx.clear(CGRect(x: 0, y: 0, width: pxW, height: pxH))
        frameCtx.draw(staticBg, in: CGRect(x: 0, y: 0, width: pxW, height: pxH))
        frameCtx.scaleBy(x: scale, y: scale)

        var lWinAlpha: CGFloat = 1.0
        var rWinAlpha: CGFloat = 1.0
        var rRunning = [0, 1, 2, 3] // idx 1 = Safari, idx 2 = Telegram
        var click = false
        var ripple: CGFloat = 0
        var lCursor = CGPoint(x: lWinRect.midX, y: lWinRect.midY)
        var rCursor = CGPoint(x: rWinRect.midX, y: rWinRect.midY)

        if t < 0.24 {
            let p = easeInOutCubic(t / 0.24)
            lCursor = CGPoint(x: lerp(lWinRect.midX, lCloseBtn.x, p), y: lerp(lWinRect.midY, lCloseBtn.y, p))
            rCursor = CGPoint(x: lerp(rWinRect.midX, rCloseBtn.x, p), y: lerp(rWinRect.midY, rCloseBtn.y, p))
        } else if t < 0.36 {
            lCursor = lCloseBtn
            rCursor = rCloseBtn
            click = (t >= 0.28 && t <= 0.34)
            ripple = clamp((t - 0.28) / 0.08)
        } else if t < 0.56 {
            let p = easeInOutCubic((t - 0.36) / 0.20)
            lWinAlpha = 1.0 - p
            rWinAlpha = 1.0 - p
            lCursor = CGPoint(x: lCloseBtn.x + 12 * p, y: lCloseBtn.y - 18 * p)
            rCursor = CGPoint(x: rCloseBtn.x + 12 * p, y: rCloseBtn.y - 18 * p)
            if t > 0.44 { rRunning = [0, 2, 3] } // Safari completely quit! Telegram stays!
        } else {
            lWinAlpha = 0
            rWinAlpha = 0
            rRunning = [0, 2, 3]
            lCursor = CGPoint(x: lCloseBtn.x + 12, y: lCloseBtn.y - 18)
            rCursor = CGPoint(x: rCloseBtn.x + 12, y: rCloseBtn.y - 18)
        }

        if lWinAlpha > 0.01 {
            frameCtx.saveGState()
            frameCtx.setAlpha(lWinAlpha)
            frameCtx.draw(safariImg, in: lWinRect)
            frameCtx.restoreGState()
        }
        if rWinAlpha > 0.01 {
            frameCtx.saveGState()
            frameCtx.setAlpha(rWinAlpha)
            frameCtx.draw(safariImg, in: rWinRect)
            frameCtx.restoreGState()
        }

        Draw.drawRealDock(ctx: frameCtx, center: lDockCenter, width: 370, icons: dockIcons, runningIndices: [0, 1, 2, 3])
        Draw.drawRealDock(
            ctx: frameCtx,
            center: rDockCenter,
            width: 370,
            icons: dockIcons,
            runningIndices: rRunning,
            labelIndex: t > 0.48 ? 2 : nil,
            labelText: lang == .ru ? "Telegram • В фоне" : "Telegram • In Background"
        )

        // Status chips appear cleanly after Safari window finishes closing
        if t > 0.56 {
            let fadeP = easeOutCubic(clamp((t - 0.56) / 0.12))
            frameCtx.saveGState()
            frameCtx.setAlpha(fadeP)

            let lChip = CGRect(x: leftCard.midX - 175, y: leftCard.midY + 25, width: 350, height: 42)
            let lp = CGPath(roundedRect: lChip, cornerWidth: 12, cornerHeight: 12, transform: nil)
            frameCtx.setFillColor(NSColor(red: 0.42, green: 0.10, blue: 0.12, alpha: 0.55).cgColor)
            frameCtx.addPath(lp); frameCtx.fillPath()
            frameCtx.setStrokeColor(Palette.coralDot.withAlphaComponent(0.5).cgColor)
            frameCtx.setLineWidth(1.2)
            frameCtx.addPath(lp); frameCtx.strokePath()
            Draw.drawText(ctx: frameCtx, lang == .ru ? "• Точка под Safari осталась • Процесс в RAM" : "• Safari dot remains • Process stays in RAM", at: CGPoint(x: lChip.midX, y: lChip.midY), size: 12.5, weight: .semibold, color: Palette.primaryText, centerX: true, centerY: true)

            let rChip = CGRect(x: rightCard.midX - 185, y: rightCard.midY + 25, width: 370, height: 42)
            let rp = CGPath(roundedRect: rChip, cornerWidth: 12, cornerHeight: 12, transform: nil)
            frameCtx.setFillColor(NSColor(red: 0.08, green: 0.30, blue: 0.16, alpha: 0.55).cgColor)
            frameCtx.addPath(rp); frameCtx.fillPath()
            frameCtx.setStrokeColor(Palette.greenDot.withAlphaComponent(0.5).cgColor)
            frameCtx.setLineWidth(1.2)
            frameCtx.addPath(rp); frameCtx.strokePath()
            Draw.drawText(ctx: frameCtx, lang == .ru ? "✓ Safari завершён (⌘Q) • Вкладки сохранены" : "✓ Safari Quit (⌘Q) • Tabs Preserved", at: CGPoint(x: rChip.midX, y: rChip.midY), size: 12.5, weight: .semibold, color: Palette.primaryText, centerX: true, centerY: true)

            frameCtx.restoreGState()
        }

        Draw.drawCursor(ctx: frameCtx, at: lCursor, clicking: click, rippleProgress: ripple)
        Draw.drawCursor(ctx: frameCtx, at: rCursor, clicking: click, rippleProgress: ripple)

        frameCtx.restoreGState()
        CGImageDestinationAddImage(dest, frameCtx.makeImage()!, fp)
    }

    if CGImageDestinationFinalize(dest) {
        let sz = (try? FileManager.default.attributesOfItem(atPath: outputPath)[.size] as? Int) ?? 0
        print("Saved 4K GIF \(outputPath) (\(pxW)x\(pxH), \(String(format: "%.2f MB", Double(sz)/1048576.0)))")
    }
}

// MARK: - Generator 3: 4K Silky UI Flow (3840x2160)

@MainActor
func generateUIFlow4K(outputPath: String, lang: Language) {
    let ptW: CGFloat = 1280
    let ptH: CGFloat = 720
    let scale: CGFloat = 1.5 // 1920x1080 Full HD!
    let pxW = Int(ptW * scale)
    let pxH = Int(ptH * scale)
    let frameCount = 165 // Smooth 3.3s loop @ 50fps browser-max
    let delay = 0.02

    let icons: [(String, CGImage?)] = [
        ("Telegram", AssetsStore.appIcon(key: "tg", paths: ["/Applications/Telegram.app"])),
        ("Discord", AssetsStore.appIcon(key: "dc", paths: ["/Applications/Discord.app"])),
        ("Spotify", AssetsStore.appIcon(key: "sp", paths: ["/Applications/Spotify.app"])),
        ("Music", AssetsStore.appIcon(key: "music", paths: ["/System/Applications/Music.app"]))
    ]

    let staticBg = AssetsStore.srgbImage(width: pxW, height: pxH) { ctx in
        ctx.scaleBy(x: scale, y: scale)
        Draw.drawFrostedBackground(ctx: ctx, width: ptW, height: ptH)

        // Subtle macOS Menu Bar at top
        ctx.setFillColor(NSColor(white: 0.08, alpha: 0.55).cgColor)
        ctx.fill(CGRect(x: 0, y: ptH - 28, width: ptW, height: 28))
        Draw.drawText(ctx: ctx, "Finder   File   Edit   View   Window   Help", at: CGPoint(x: 24, y: ptH - 14), size: 12, weight: .medium, color: Palette.primaryText, centerY: true)

        // DockFlow icon highlighted in menu bar
        let pill = CGRect(x: ptW / 2 - 22, y: ptH - 24, width: 44, height: 20)
        let pp = CGPath(roundedRect: pill, cornerWidth: 5, cornerHeight: 5, transform: nil)
        ctx.setFillColor(NSColor(white: 1, alpha: 0.22).cgColor)
        ctx.addPath(pp); ctx.fillPath()
        let miniWin = CGRect(x: ptW / 2 - 8, y: ptH - 19, width: 16, height: 10)
        let mp = CGPath(roundedRect: miniWin, cornerWidth: 2, cornerHeight: 2, transform: nil)
        ctx.setStrokeColor(NSColor.white.cgColor); ctx.setLineWidth(1.5)
        ctx.addPath(mp); ctx.strokePath()

        // Left side typography showcase
        let leftX: CGFloat = 72
        Draw.drawText(ctx: ctx, "DockFlow", at: CGPoint(x: leftX, y: 455), size: 46, weight: .bold, color: Palette.primaryText)
        let verRect = CGRect(x: leftX + 225, y: 467, width: 76, height: 30)
        let vp = CGPath(roundedRect: verRect, cornerWidth: 15, cornerHeight: 15, transform: nil)
        ctx.setFillColor(Palette.activePill.cgColor); ctx.addPath(vp); ctx.fillPath()
        Draw.drawText(ctx: ctx, "v2.0", at: CGPoint(x: verRect.midX, y: verRect.midY), size: 14, weight: .bold, color: Palette.activeText, mono: true, centerX: true, centerY: true)

        let feats = lang == .ru
            ? [
                "• Мягкое полупрозрачное стекло под цвет обоев",
                "• Плавная смена высоты вкладок с лёгким блюром",
                "• Приятная физика тумблеров и скользящие пилюли",
                "• Мгновенное закрытие повторным кликом"
            ]
            : [
                "• Soft translucent glass blended with your wallpaper",
                "• Smooth height resizing and gentle blur tab transitions",
                "• Tactile switch physics & sliding selection pills",
                "• Instant second-click toggle in the menu bar"
            ]

        for (idx, line) in feats.enumerated() {
            Draw.drawText(ctx: ctx, line, at: CGPoint(x: leftX, y: CGFloat(395 - idx * 38)), size: 16, weight: .medium, color: Palette.secondaryText)
        }
    }

    let url = URL(fileURLWithPath: outputPath)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frameCount, nil)!
    CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    let fp = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay, kCGImagePropertyGIFUnclampedDelayTime: delay]] as CFDictionary

    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let frameCtx = CGContext(data: nil, width: pxW, height: pxH, bitsPerComponent: 8, bytesPerRow: pxW * 4, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

    // Pre-cache UI panel states or render cleanly using ImageRenderer per key phase -> even smoother!
    let panelTopY: CGFloat = ptH - 48 // pinned neatly right under top Menu Bar!
    let panelCenterX: CGFloat = 925
    let panelPresentationScale: CGFloat = 1.20 // 1.20 * 3.0 = exact 3.60x pixel match!
    var cachedPanels: [String: CGImage] = [:]

    // Helper: non-overlapping fade-out (0..0.42) -> crisp fade-in (0.43..1.0) without GIF blur dither bloat
    func nonOverlappingTransition(_ trans: CGFloat) -> (outOpacity: Double, outY: CGFloat, inOpacity: Double, inY: CGFloat) {
        let outP = clamp(trans / 0.42)
        let inP = clamp((trans - 0.43) / 0.57)
        return (
            outOpacity: Double(1.0 - easeInOutCubic(outP)),
            outY: -5.0 * outP,
            inOpacity: Double(easeInOutCubic(inP)),
            inY: 6.0 * (1.0 - easeOutCubic(inP))
        )
    }

    for f in 0..<frameCount {
        let t = CGFloat(f) / CGFloat(frameCount)
        frameCtx.saveGState()
        frameCtx.clear(CGRect(x: 0, y: 0, width: pxW, height: pxH))
        frameCtx.draw(staticBg, in: CGRect(x: 0, y: 0, width: pxW, height: pxH))
        frameCtx.scaleBy(x: scale, y: scale)

        var targetTab = 0
        var tabPillPos: CGFloat = 0
        var toggleProgress: CGFloat = 1.0
        var midPillPos: CGFloat = 0.0
        var h: CGFloat = 427
        var opacities: (Double, Double, Double) = (1, 0, 0)
        var yOffsets: (CGFloat, CGFloat, CGFloat) = (0, 0, 0)
        var panelAlpha: CGFloat = 1
        var panelScale: CGFloat = 1

        let togglePt = CGPoint(x: panelCenterX + 185 * panelPresentationScale, y: panelTopY - 82 * panelPresentationScale)
        let midPt = CGPoint(x: panelCenterX - 55 * panelPresentationScale, y: panelTopY - 344 * panelPresentationScale)
        let tab1Pt = CGPoint(x: panelCenterX + 68 * panelPresentationScale, y: panelTopY - 22 * panelPresentationScale)
        let tab2Pt = CGPoint(x: panelCenterX + 162 * panelPresentationScale, y: panelTopY - 22 * panelPresentationScale)
        let tab0Pt = CGPoint(x: panelCenterX - 10 * panelPresentationScale, y: panelTopY - 22 * panelPresentationScale)

        var cursor = CGPoint(x: ptW / 2, y: ptH - 14)
        var click = false
        var ripple: CGFloat = 0

        if t < 0.10 {
            let p = easeOutCubic(t / 0.10)
            panelAlpha = p
            panelScale = lerp(0.95, 1.0, p)
            cursor = CGPoint(x: lerp(ptW / 2, togglePt.x, easeInOutCubic(t / 0.10)), y: lerp(ptH - 14, togglePt.y, easeInOutCubic(t / 0.10)))
        } else if t < 0.24 {
            let p = clamp((t - 0.12) / 0.10)
            toggleProgress = 1.0 - easeInOutCubic(p)
            cursor = togglePt
            click = (t >= 0.10 && t <= 0.13)
            ripple = clamp((t - 0.10) / 0.05)
        } else if t < 0.36 {
            let moveP = easeInOutCubic(clamp((t - 0.24) / 0.06))
            cursor = CGPoint(x: lerp(togglePt.x, midPt.x, moveP), y: lerp(togglePt.y, midPt.y, moveP))
            toggleProgress = 0.0
            let slideP = easeInOutCubic(clamp((t - 0.30) / 0.06))
            midPillPos = slideP
            click = (t >= 0.29 && t <= 0.32)
            ripple = clamp((t - 0.29) / 0.05)
        } else if t < 0.54 {
            targetTab = t >= 0.42 ? 1 : 0
            toggleProgress = 0.0
            midPillPos = 1.0
            let moveP = easeInOutCubic(clamp((t - 0.36) / 0.06))
            cursor = CGPoint(x: lerp(midPt.x, tab1Pt.x, moveP), y: lerp(midPt.y, tab1Pt.y, moveP))
            click = (t >= 0.41 && t <= 0.44)
            ripple = clamp((t - 0.41) / 0.05)
            let trans = clamp((t - 0.42) / 0.12)
            let smooth = easeInOutCubic(trans)
            tabPillPos = lerp(0.0, 1.0, smooth)
            h = lerp(427, 386, smooth)
            let tr = nonOverlappingTransition(trans)
            opacities = (tr.outOpacity, tr.inOpacity, 0)
            yOffsets = (tr.outY, tr.inY, 0)
        } else if t < 0.74 {
            targetTab = t >= 0.60 ? 2 : 1
            let moveP = easeInOutCubic(clamp((t - 0.54) / 0.06))
            cursor = CGPoint(x: lerp(tab1Pt.x, tab2Pt.x, moveP), y: lerp(tab1Pt.y, tab2Pt.y, moveP))
            click = (t >= 0.59 && t <= 0.62)
            ripple = clamp((t - 0.59) / 0.05)
            let trans = clamp((t - 0.60) / 0.13)
            let smooth = easeInOutCubic(trans)
            tabPillPos = lerp(1.0, 2.0, smooth)
            h = lerp(386, 346, smooth)
            let tr = nonOverlappingTransition(trans)
            opacities = (0, tr.outOpacity, tr.inOpacity)
            yOffsets = (0, tr.outY, tr.inY)
        } else if t < 0.94 {
            targetTab = t >= 0.80 ? 0 : 2
            toggleProgress = 1.0
            midPillPos = 0.0
            let moveP = easeInOutCubic(clamp((t - 0.74) / 0.06))
            cursor = CGPoint(x: lerp(tab2Pt.x, tab0Pt.x, moveP), y: lerp(tab2Pt.y, tab0Pt.y, moveP))
            click = (t >= 0.79 && t <= 0.82)
            ripple = clamp((t - 0.79) / 0.05)
            let trans = clamp((t - 0.80) / 0.13)
            let smooth = easeInOutCubic(trans)
            tabPillPos = lerp(2.0, 0.0, smooth)
            h = lerp(346, 427, smooth)
            let tr = nonOverlappingTransition(trans)
            opacities = (tr.inOpacity, 0, tr.outOpacity)
            yOffsets = (tr.inY, 0, tr.outY)
        } else {
            targetTab = 0
            let moveP = easeInOutCubic(clamp((t - 0.94) / 0.06))
            cursor = CGPoint(x: lerp(tab0Pt.x, ptW / 2, moveP), y: lerp(tab0Pt.y, ptH - 14, moveP))
            tabPillPos = 0
            toggleProgress = 1.0
            midPillPos = 0.0
            h = 427
            opacities = (1, 0, 0)
        }

        let roundedH = (h * 2).rounded() / 2
        let stateKey = String(
            format: "%d-%.2f-%.2f-%.2f-%.1f-%.2f-%.2f-%.2f",
            targetTab, tabPillPos, toggleProgress, midPillPos, roundedH, opacities.0, opacities.1, opacities.2
        )
        let panelImg: CGImage
        if let hit = cachedPanels[stateKey] {
            panelImg = hit
        } else {
            let panelView = UIPanelSnapshotView(
                lang: lang,
                targetTab: targetTab,
                tabPillPosition: tabPillPos,
                toggleProgress: toggleProgress,
                midPillPosition: midPillPos,
                panelHeight: roundedH,
                activeTabLayerOpacity: opacities,
                activeTabYOffset: yOffsets,
                icons: icons
            )
            let rendered = AssetsStore.renderSwiftUI(panelView, scale: 1.8) // Exact 1:1 1080p pixel mapping!
            cachedPanels[stateKey] = rendered
            panelImg = rendered
        }

        let drawW = 446 * panelPresentationScale * panelScale
        let drawH = roundedH * panelPresentationScale * panelScale
        let drawRect = CGRect(
            x: (panelCenterX - drawW / 2).rounded(),
            y: (panelTopY - drawH).rounded(),
            width: drawW,
            height: drawH
        )

        frameCtx.saveGState()
        frameCtx.setAlpha(panelAlpha)
        frameCtx.draw(panelImg, in: drawRect)
        frameCtx.restoreGState()

        Draw.drawCursor(ctx: frameCtx, at: cursor, clicking: click, rippleProgress: ripple)

        frameCtx.restoreGState()
        CGImageDestinationAddImage(dest, frameCtx.makeImage()!, fp)
    }

    if CGImageDestinationFinalize(dest) {
        let sz = (try? FileManager.default.attributesOfItem(atPath: outputPath)[.size] as? Int) ?? 0
        print("Saved 4K GIF \(outputPath) (\(pxW)x\(pxH), \(String(format: "%.2f MB", Double(sz)/1048576.0)))")
    }
}

// MARK: - Main Execution

_ = NSApplication.shared
MainActor.assumeIsolated {
    let assetsDir = "/Users/minosssh1./.gemini/antigravity/scratch/DockMinimizer/assets"

    let uiOnly = CommandLine.arguments.contains("--ui-only")
    print("Rendering 4K (3840x2160) 60/50fps GIFs matching DockFlow v2.2.0...")
    generateUIFlow4K(outputPath: "\(assetsDir)/demo_ui_flow_ru.gif", lang: .ru)
    generateUIFlow4K(outputPath: "\(assetsDir)/demo_ui_flow_en.gif", lang: .en)
    if !uiOnly {
        generateDockMinimize4K(outputPath: "\(assetsDir)/demo_dock_minimize_ru.gif", lang: .ru)
        generateDockMinimize4K(outputPath: "\(assetsDir)/demo_dock_minimize_en.gif", lang: .en)
        generateQuitOnClose4K(outputPath: "\(assetsDir)/demo_quit_on_close_ru.gif", lang: .ru)
        generateQuitOnClose4K(outputPath: "\(assetsDir)/demo_quit_on_close_en.gif", lang: .en)
    }
    print("All requested 4K GIFs complete!")
}
