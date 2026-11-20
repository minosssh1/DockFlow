import AppKit
import ImageIO
import UniformTypeIdentifiers

// MARK: - Helper Math
func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
    return a + (b - a) * t
}

func easeInOutCubic(_ t: CGFloat) -> CGFloat {
    return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
}

func easeOutBack(_ t: CGFloat) -> CGFloat {
    let c1: CGFloat = 1.70158
    let c3 = c1 + 1
    return 1 + c3 * pow(t - 1, 3) + c1 * pow(t - 1, 2)
}

// MARK: - Drawing Utilities
struct DrawUtils {
    static func drawBackground(ctx: CGContext, rect: CGRect) {
        let colors = [
            NSColor(red: 0.08, green: 0.09, blue: 0.13, alpha: 1.0).cgColor,
            NSColor(red: 0.04, green: 0.05, blue: 0.07, alpha: 1.0).cgColor
        ] as CFArray
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0])!
        ctx.drawLinearGradient(gradient, start: CGPoint(x: rect.midX, y: rect.maxY), end: CGPoint(x: rect.midX, y: rect.minY), options: [])

        let spotColors = [
            NSColor(red: 0.25, green: 0.35, blue: 0.70, alpha: 0.20).cgColor,
            NSColor(red: 0.15, green: 0.20, blue: 0.40, alpha: 0.0).cgColor
        ] as CFArray
        let spotGradient = CGGradient(colorsSpace: colorSpace, colors: spotColors, locations: [0.0, 1.0])!
        ctx.drawRadialGradient(spotGradient, startCenter: CGPoint(x: rect.midX, y: rect.midY + 50), startRadius: 0, endCenter: CGPoint(x: rect.midX, y: rect.midY + 50), endRadius: 380, options: [])
    }

    static func drawText(ctx: CGContext, text: String, point: CGPoint, font: NSFont, color: NSColor, alignCenter: Bool = false) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        let drawPoint = alignCenter ? CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2) : point
        str.draw(at: drawPoint)
    }

    static func drawHeader(ctx: CGContext, width: CGFloat, topY: CGFloat, title: String, subtitle: String) {
        // App icon badge
        let iconRect = CGRect(x: width / 2 - 15, y: topY - 14, width: 30, height: 30)
        let iconPath = CGPath(roundedRect: iconRect, cornerWidth: 7, cornerHeight: 7, transform: nil)
        ctx.saveGState()
        ctx.addPath(iconPath)
        ctx.clip()
        let iconColors = [
            NSColor(red: 0.25, green: 0.55, blue: 1.0, alpha: 1.0).cgColor,
            NSColor(red: 0.65, green: 0.35, blue: 0.95, alpha: 1.0).cgColor
        ] as CFArray
        let iconGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: iconColors, locations: [0, 1])!
        ctx.drawLinearGradient(iconGrad, start: CGPoint(x: iconRect.minX, y: iconRect.maxY), end: CGPoint(x: iconRect.maxX, y: iconRect.minY), options: [])
        ctx.restoreGState()

        // White inner symbol
        ctx.saveGState()
        let miniWin = CGRect(x: iconRect.minX + 7, y: iconRect.minY + 8, width: 16, height: 13)
        let miniPath = CGPath(roundedRect: miniWin, cornerWidth: 2.5, cornerHeight: 2.5, transform: nil)
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(1.8)
        ctx.addPath(miniPath)
        ctx.strokePath()
        ctx.restoreGState()

        // Title
        drawText(ctx: ctx, text: title, point: CGPoint(x: width / 2, y: topY - 33), font: NSFont.systemFont(ofSize: 20, weight: .bold), color: .white, alignCenter: true)
        // Subtitle
        drawText(ctx: ctx, text: subtitle, point: CGPoint(x: width / 2, y: topY - 50), font: NSFont.systemFont(ofSize: 12.5, weight: .medium), color: NSColor(white: 0.70, alpha: 1.0), alignCenter: true)
    }

    static func drawWindow(ctx: CGContext, rect: CGRect, title: String, scale: CGFloat = 1.0, alpha: CGFloat = 1.0, hoverClose: Bool = false) {
        guard alpha > 0.01 && scale > 0.05 else { return }
        ctx.saveGState()
        
        let midX = rect.midX
        let midY = rect.midY
        ctx.translateBy(x: midX, y: midY)
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -midX, y: -midY)
        ctx.setAlpha(alpha)

        // Drop shadow
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 24, color: NSColor(white: 0, alpha: 0.50).cgColor)
        let winPath = CGPath(roundedRect: rect, cornerWidth: 10, cornerHeight: 10, transform: nil)
        ctx.setFillColor(NSColor(red: 0.13, green: 0.14, blue: 0.18, alpha: 0.98).cgColor)
        ctx.addPath(winPath)
        ctx.fillPath()
        ctx.restoreGState()

        // Border
        ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.14).cgColor)
        ctx.setLineWidth(1)
        ctx.addPath(winPath)
        ctx.strokePath()

        // Titlebar
        let titlebarRect = CGRect(x: rect.minX, y: rect.maxY - 28, width: rect.width, height: 28)
        ctx.saveGState()
        let clipPath = CGPath(roundedRect: rect, cornerWidth: 10, cornerHeight: 10, transform: nil)
        ctx.addPath(clipPath)
        ctx.clip()
        ctx.setFillColor(NSColor(red: 0.17, green: 0.18, blue: 0.23, alpha: 1.0).cgColor)
        ctx.fill(titlebarRect)

        // Titlebar divider
        ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.06).cgColor)
        ctx.setLineWidth(1)
        ctx.move(to: CGPoint(x: rect.minX, y: rect.maxY - 28))
        ctx.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - 28))
        ctx.strokePath()
        ctx.restoreGState()

        // Traffic lights
        let tlY = rect.maxY - 14
        let redCenter = CGPoint(x: rect.minX + 16, y: tlY)
        let yellowCenter = CGPoint(x: rect.minX + 32, y: tlY)
        let greenCenter = CGPoint(x: rect.minX + 48, y: tlY)

        // Red
        ctx.setFillColor(NSColor(red: 1.0, green: 0.37, blue: 0.34, alpha: 1.0).cgColor)
        ctx.fillEllipse(in: CGRect(x: redCenter.x - 5.5, y: redCenter.y - 5.5, width: 11, height: 11))
        if hoverClose {
            ctx.setStrokeColor(NSColor(red: 0.35, green: 0.05, blue: 0.05, alpha: 0.95).cgColor)
            ctx.setLineWidth(1.4)
            ctx.move(to: CGPoint(x: redCenter.x - 2.5, y: redCenter.y - 2.5))
            ctx.addLine(to: CGPoint(x: redCenter.x + 2.5, y: redCenter.y + 2.5))
            ctx.move(to: CGPoint(x: redCenter.x + 2.5, y: redCenter.y - 2.5))
            ctx.addLine(to: CGPoint(x: redCenter.x - 2.5, y: redCenter.y + 2.5))
            ctx.strokePath()
        }

        // Yellow & Green
        ctx.setFillColor(NSColor(red: 1.0, green: 0.74, blue: 0.18, alpha: 1.0).cgColor)
        ctx.fillEllipse(in: CGRect(x: yellowCenter.x - 5.5, y: yellowCenter.y - 5.5, width: 11, height: 11))
        ctx.setFillColor(NSColor(red: 0.16, green: 0.78, blue: 0.25, alpha: 1.0).cgColor)
        ctx.fillEllipse(in: CGRect(x: greenCenter.x - 5.5, y: greenCenter.y - 5.5, width: 11, height: 11))

        // Title text
        drawText(ctx: ctx, text: title, point: CGPoint(x: rect.midX, y: tlY - 5.5), font: NSFont.systemFont(ofSize: 11, weight: .medium), color: NSColor(white: 0.7, alpha: 1.0), alignCenter: true)

        // Window body skeleton
        let bodyTop = rect.maxY - 42
        let barColors: [(CGFloat, CGFloat)] = [(0.6, 0.75), (0.4, 0.55), (0.5, 0.65), (0.3, 0.45)]
        for (i, (wPct, a)) in barColors.enumerated() {
            let lineY = bodyTop - CGFloat(i * 15)
            guard lineY > rect.minY + 14 else { break }
            let lineRect = CGRect(x: rect.minX + 16, y: lineY, width: (rect.width - 32) * wPct, height: 7)
            ctx.setFillColor(NSColor(white: 1.0, alpha: a * 0.18).cgColor)
            ctx.fill(lineRect)
        }

        ctx.restoreGState()
    }

    static func drawDock(ctx: CGContext, center: CGPoint, width: CGFloat, activeIndex: Int, runningIndices: [Int], bounceOffset: CGFloat = 0) {
        let dockHeight: CGFloat = 48
        let dockRect = CGRect(x: center.x - width / 2, y: center.y - dockHeight / 2, width: width, height: dockHeight)
        
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 18, color: NSColor(white: 0, alpha: 0.55).cgColor)
        let dockPath = CGPath(roundedRect: dockRect, cornerWidth: 16, cornerHeight: 16, transform: nil)
        ctx.setFillColor(NSColor(red: 0.12, green: 0.13, blue: 0.18, alpha: 0.88).cgColor)
        ctx.addPath(dockPath)
        ctx.fillPath()
        ctx.restoreGState()

        ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.16).cgColor)
        ctx.setLineWidth(1)
        ctx.addPath(dockPath)
        ctx.strokePath()

        let iconCount = 6
        let spacing = width / CGFloat(iconCount + 1)

        let iconData: [(NSColor, NSColor, String)] = [
            (NSColor(red: 0.15, green: 0.55, blue: 0.95, alpha: 1), NSColor(red: 0.05, green: 0.35, blue: 0.75, alpha: 1), "Finder"),
            (NSColor(red: 0.20, green: 0.75, blue: 0.35, alpha: 1), NSColor(red: 0.10, green: 0.55, blue: 0.25, alpha: 1), "Chat"),
            (NSColor(red: 0.95, green: 0.50, blue: 0.15, alpha: 1), NSColor(red: 0.85, green: 0.25, blue: 0.15, alpha: 1), "Safari"),
            (NSColor(red: 0.35, green: 0.45, blue: 0.95, alpha: 1), NSColor(red: 0.65, green: 0.25, blue: 0.85, alpha: 1), "DockFlow"),
            (NSColor(red: 0.95, green: 0.25, blue: 0.45, alpha: 1), NSColor(red: 0.80, green: 0.15, blue: 0.30, alpha: 1), "Music"),
            (NSColor(red: 0.28, green: 0.30, blue: 0.36, alpha: 1), NSColor(red: 0.16, green: 0.17, blue: 0.22, alpha: 1), "Term")
        ]

        for i in 0..<iconCount {
            let cx = dockRect.minX + spacing * CGFloat(i + 1)
            let isTarget = (i == activeIndex)
            let cy = center.y + (isTarget ? bounceOffset : 0)

            let iconSize: CGFloat = 32
            let iconBox = CGRect(x: cx - iconSize / 2, y: cy - iconSize / 2, width: iconSize, height: iconSize)
            
            ctx.saveGState()
            let iconPath = CGPath(roundedRect: iconBox, cornerWidth: 8, cornerHeight: 8, transform: nil)
            ctx.addPath(iconPath)
            ctx.clip()

            let (c1, c2, tag) = iconData[i]
            let colors = [c1.cgColor, c2.cgColor] as CFArray
            let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            ctx.drawLinearGradient(grad, start: CGPoint(x: iconBox.minX, y: iconBox.maxY), end: CGPoint(x: iconBox.maxX, y: iconBox.minY), options: [])
            ctx.restoreGState()

            // Icon graphics
            if tag == "DockFlow" {
                let winGlyph = CGRect(x: cx - 7, y: cy - 5, width: 14, height: 10)
                let gp = CGPath(roundedRect: winGlyph, cornerWidth: 2, cornerHeight: 2, transform: nil)
                ctx.setStrokeColor(NSColor.white.cgColor)
                ctx.setLineWidth(1.5)
                ctx.addPath(gp)
                ctx.strokePath()
            } else if tag == "Safari" {
                ctx.setStrokeColor(NSColor.white.cgColor)
                ctx.setLineWidth(1.4)
                ctx.strokeEllipse(in: CGRect(x: cx - 7, y: cy - 7, width: 14, height: 14))
                ctx.setFillColor(NSColor.white.cgColor)
                ctx.fillEllipse(in: CGRect(x: cx - 2, y: cy - 2, width: 4, height: 4))
            } else if tag == "Finder" {
                let smile = CGMutablePath()
                smile.addArc(center: CGPoint(x: cx, y: cy + 1), radius: 6, startAngle: 0.2 * .pi, endAngle: 0.8 * .pi, clockwise: false)
                ctx.setStrokeColor(NSColor.white.cgColor)
                ctx.setLineWidth(1.5)
                ctx.addPath(smile)
                ctx.strokePath()
            } else if tag == "Music" {
                drawText(ctx: ctx, text: "♫", point: CGPoint(x: cx, y: cy - 6), font: NSFont.systemFont(ofSize: 13, weight: .bold), color: .white, alignCenter: true)
            } else if tag == "Term" {
                drawText(ctx: ctx, text: ">_", point: CGPoint(x: cx, y: cy - 5), font: NSFont.systemFont(ofSize: 10, weight: .bold), color: .white, alignCenter: true)
            } else {
                drawText(ctx: ctx, text: "●", point: CGPoint(x: cx, y: cy - 6), font: NSFont.systemFont(ofSize: 11, weight: .bold), color: .white, alignCenter: true)
            }

            // Glow ring for active
            if isTarget {
                ctx.setStrokeColor(NSColor(red: 0.45, green: 0.75, blue: 1.0, alpha: 0.85).cgColor)
                ctx.setLineWidth(1.8)
                ctx.addPath(iconPath)
                ctx.strokePath()
            }

            // Running indicator dot
            if runningIndices.contains(i) {
                let dotY = dockRect.minY + 4
                ctx.setFillColor(NSColor.white.cgColor)
                ctx.fillEllipse(in: CGRect(x: cx - 2.5, y: dotY - 2.5, width: 5, height: 5))
            }
        }
    }

    static func drawCursor(ctx: CGContext, at: CGPoint, isClicking: Bool) {
        ctx.saveGState()
        if isClicking {
            ctx.setStrokeColor(NSColor(red: 0.4, green: 0.75, blue: 1.0, alpha: 0.7).cgColor)
            ctx.setLineWidth(2.2)
            ctx.strokeEllipse(in: CGRect(x: at.x - 14, y: at.y - 14, width: 28, height: 28))
        }

        ctx.setShadow(offset: CGSize(width: 1, height: -2), blur: 5, color: NSColor(white: 0, alpha: 0.65).cgColor)

        let path = CGMutablePath()
        path.move(to: at)
        path.addLine(to: CGPoint(x: at.x + 11, y: at.y - 11))
        path.addLine(to: CGPoint(x: at.x + 5, y: at.y - 11))
        path.addLine(to: CGPoint(x: at.x + 8, y: at.y - 17))
        path.addLine(to: CGPoint(x: at.x + 4.5, y: at.y - 18.5))
        path.addLine(to: CGPoint(x: at.x + 1.5, y: at.y - 12.5))
        path.addLine(to: CGPoint(x: at.x, y: at.y - 15))
        path.closeSubpath()

        ctx.setFillColor(NSColor.black.cgColor)
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(1.4)
        ctx.addPath(path)
        ctx.drawPath(using: .fillStroke)
        ctx.restoreGState()
    }

    static func drawCurvedArrow(ctx: CGContext, from: CGPoint, to: CGPoint, progress: CGFloat, isDownward: Bool) {
        ctx.saveGState()
        let path = CGMutablePath()
        path.move(to: from)
        let ctrlX = (from.x + to.x) / 2 + (isDownward ? 30 : -30)
        let ctrlY = (from.y + to.y) / 2
        path.addQuadCurve(to: to, control: CGPoint(x: ctrlX, y: ctrlY))

        let dashes: [CGFloat] = [5, 4]
        ctx.setLineDash(phase: -progress * 18, lengths: dashes)
        ctx.setStrokeColor(NSColor(red: 0.45, green: 0.70, blue: 1.0, alpha: 0.75).cgColor)
        ctx.setLineWidth(2.2)
        ctx.addPath(path)
        ctx.strokePath()
        ctx.restoreGState()
    }
}

// MARK: - GIF 1 Generator: Dock Minimize & Restore (Dark Theme)
func generateDockMinimizeGIF(outputPath: String) {
    let width = 780
    let height = 440
    let frameCount = 36
    let delay = 0.08
    
    let url = URL(fileURLWithPath: outputPath)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frameCount, nil) else {
        print("Failed to create destination for \(outputPath)")
        return
    }

    let gifProps: [String: Any] = [
        kCGImagePropertyGIFDictionary as String: [
            kCGImagePropertyGIFLoopCount as String: 0
        ]
    ]
    CGImageDestinationSetProperties(dest, gifProps as CFDictionary)

    let frameProps: [String: Any] = [
        kCGImagePropertyGIFDictionary as String: [
            kCGImagePropertyGIFDelayTime as String: delay
        ]
    ]

    for frame in 0..<frameCount {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let ctx = NSGraphicsContext.current!.cgContext

        let fullRect = CGRect(x: 0, y: 0, width: width, height: height)
        DrawUtils.drawBackground(ctx: ctx, rect: fullRect)

        DrawUtils.drawHeader(ctx: ctx, width: CGFloat(width), topY: CGFloat(height - 18), title: "DockFlow", subtitle: "Плавное сворачивание и разворачивание по клику в Доке")

        let cardW: CGFloat = 355
        let cardH: CGFloat = 320
        let cardY: CGFloat = 35

        let leftCardRect = CGRect(x: 22, y: cardY, width: cardW, height: cardH)
        let rightCardRect = CGRect(x: CGFloat(width) - cardW - 22, y: cardY, width: cardW, height: cardH)

        for cardRect in [leftCardRect, rightCardRect] {
            ctx.saveGState()
            let cPath = CGPath(roundedRect: cardRect, cornerWidth: 16, cornerHeight: 16, transform: nil)
            ctx.setFillColor(NSColor(red: 0.10, green: 0.11, blue: 0.15, alpha: 0.75).cgColor)
            ctx.addPath(cPath)
            ctx.fillPath()
            ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.09).cgColor)
            ctx.setLineWidth(1)
            ctx.addPath(cPath)
            ctx.strokePath()
            ctx.restoreGState()
        }

        DrawUtils.drawText(ctx: ctx, text: "Клик по иконке — свернуть", point: CGPoint(x: leftCardRect.midX, y: leftCardRect.minY + 22), font: NSFont.systemFont(ofSize: 13.5, weight: .semibold), color: .white, alignCenter: true)
        DrawUtils.drawText(ctx: ctx, text: "Повторный клик — развернуть", point: CGPoint(x: rightCardRect.midX, y: rightCardRect.minY + 22), font: NSFont.systemFont(ofSize: 13.5, weight: .semibold), color: .white, alignCenter: true)

        let t = CGFloat(frame) / CGFloat(frameCount)

        let leftDockCenter = CGPoint(x: leftCardRect.midX, y: leftCardRect.minY + 72)
        let rightDockCenter = CGPoint(x: rightCardRect.midX, y: rightCardRect.minY + 72)

        // LEFT SIDE: MINIMIZING
        let leftWinRect = CGRect(x: leftCardRect.midX - 115, y: leftCardRect.maxY - 150, width: 230, height: 130)
        var leftWinScale: CGFloat = 1.0
        var leftWinAlpha: CGFloat = 1.0
        var leftCursorPos = CGPoint(x: leftCardRect.midX - 30, y: leftCardRect.midY + 15)
        var leftClicking = false
        var leftBounce: CGFloat = 0

        let targetIconX_L = leftDockCenter.x + 20
        let targetIconY_L = leftDockCenter.y + 2

        if t < 0.25 {
            let p = t / 0.25
            leftCursorPos = CGPoint(x: lerp(leftCardRect.midX - 30, targetIconX_L, easeInOutCubic(p)),
                                    y: lerp(leftCardRect.midY + 15, targetIconY_L, easeInOutCubic(p)))
        } else if t < 0.38 {
            leftCursorPos = CGPoint(x: targetIconX_L, y: targetIconY_L)
            leftClicking = (t >= 0.28 && t <= 0.34)
            leftBounce = (t >= 0.28 && t <= 0.35) ? 4 : 0
        } else if t < 0.70 {
            leftCursorPos = CGPoint(x: targetIconX_L, y: targetIconY_L)
            let p = (t - 0.38) / 0.32
            leftWinScale = lerp(1.0, 0.05, easeInOutCubic(p))
            leftWinAlpha = lerp(1.0, 0.1, p)
        } else {
            leftWinScale = 0.0
            leftWinAlpha = 0.0
            leftCursorPos = CGPoint(x: targetIconX_L, y: targetIconY_L)
        }

        let currentLeftWinRect = CGRect(
            x: lerp(leftWinRect.minX, targetIconX_L - leftWinRect.width * leftWinScale / 2, 1.0 - leftWinScale),
            y: lerp(leftWinRect.minY, leftDockCenter.y + 10, 1.0 - leftWinScale),
            width: leftWinRect.width,
            height: leftWinRect.height
        )
        DrawUtils.drawWindow(ctx: ctx, rect: currentLeftWinRect, title: "Notes — Заметки", scale: leftWinScale, alpha: leftWinAlpha)

        let arrowStart = CGPoint(x: leftCardRect.midX - 10, y: leftCardRect.midY + 45)
        let arrowEnd = CGPoint(x: leftDockCenter.x + 18, y: leftDockCenter.y + 32)
        DrawUtils.drawCurvedArrow(ctx: ctx, from: arrowStart, to: arrowEnd, progress: t, isDownward: true)

        DrawUtils.drawDock(ctx: ctx, center: leftDockCenter, width: 280, activeIndex: 3, runningIndices: [0, 1, 3, 4], bounceOffset: leftBounce)
        DrawUtils.drawCursor(ctx: ctx, at: leftCursorPos, isClicking: leftClicking)

        // RIGHT SIDE: RESTORING
        let rightWinRect = CGRect(x: rightCardRect.midX - 115, y: rightCardRect.maxY - 150, width: 230, height: 130)
        var rightWinScale: CGFloat = 0.0
        var rightWinAlpha: CGFloat = 0.0
        let targetIconX_R = rightDockCenter.x + 20
        let targetIconY_R = rightDockCenter.y + 2
        var rightCursorPos = CGPoint(x: targetIconX_R + 30, y: targetIconY_R - 15)
        var rightClicking = false
        var rightBounce: CGFloat = 0

        if t < 0.18 {
            let p = t / 0.18
            rightCursorPos = CGPoint(x: lerp(targetIconX_R + 30, targetIconX_R, easeInOutCubic(p)),
                                     y: lerp(targetIconY_R - 15, targetIconY_R, easeInOutCubic(p)))
        } else if t < 0.28 {
            rightCursorPos = CGPoint(x: targetIconX_R, y: targetIconY_R)
            rightClicking = (t >= 0.20 && t <= 0.26)
            rightBounce = (t >= 0.20 && t <= 0.26) ? 4 : 0
        } else if t < 0.60 {
            rightCursorPos = CGPoint(x: targetIconX_R, y: targetIconY_R)
            let p = (t - 0.28) / 0.32
            rightWinScale = lerp(0.05, 1.0, easeOutBack(p))
            rightWinAlpha = lerp(0.1, 1.0, p)
        } else {
            rightWinScale = 1.0
            rightWinAlpha = 1.0
            rightCursorPos = CGPoint(x: targetIconX_R, y: targetIconY_R)
        }

        let currentRightWinRect = CGRect(
            x: lerp(targetIconX_R - rightWinRect.width * rightWinScale / 2, rightWinRect.minX, rightWinScale),
            y: lerp(rightDockCenter.y + 10, rightWinRect.minY, rightWinScale),
            width: rightWinRect.width,
            height: rightWinRect.height
        )
        DrawUtils.drawWindow(ctx: ctx, rect: currentRightWinRect, title: "Notes — Заметки", scale: rightWinScale, alpha: rightWinAlpha)

        let rArrowStart = CGPoint(x: rightDockCenter.x + 22, y: rightDockCenter.y + 32)
        let rArrowEnd = CGPoint(x: rightCardRect.midX + 15, y: rightCardRect.midY + 45)
        DrawUtils.drawCurvedArrow(ctx: ctx, from: rArrowStart, to: rArrowEnd, progress: t, isDownward: false)

        DrawUtils.drawDock(ctx: ctx, center: rightDockCenter, width: 280, activeIndex: 3, runningIndices: [0, 1, 3, 4], bounceOffset: rightBounce)
        DrawUtils.drawCursor(ctx: ctx, at: rightCursorPos, isClicking: rightClicking)

        NSGraphicsContext.restoreGraphicsState()
        CGImageDestinationAddImage(dest, rep.cgImage!, frameProps as CFDictionary)
    }

    if CGImageDestinationFinalize(dest) {
        print("✅ Successfully generated \(outputPath)")
    } else {
        print("❌ Failed finalize \(outputPath)")
    }
}

// MARK: - GIF 2 Generator: Quit on Close Button (Dark Theme)
func generateQuitOnCloseGIF(outputPath: String) {
    let width = 780
    let height = 440
    let frameCount = 36
    let delay = 0.08
    
    let url = URL(fileURLWithPath: outputPath)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frameCount, nil) else {
        print("Failed to create destination for \(outputPath)")
        return
    }

    let gifProps: [String: Any] = [
        kCGImagePropertyGIFDictionary as String: [
            kCGImagePropertyGIFLoopCount as String: 0
        ]
    ]
    CGImageDestinationSetProperties(dest, gifProps as CFDictionary)

    let frameProps: [String: Any] = [
        kCGImagePropertyGIFDictionary as String: [
            kCGImagePropertyGIFDelayTime as String: delay
        ]
    ]

    for frame in 0..<frameCount {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let ctx = NSGraphicsContext.current!.cgContext

        let fullRect = CGRect(x: 0, y: 0, width: width, height: height)
        DrawUtils.drawBackground(ctx: ctx, rect: fullRect)

        DrawUtils.drawHeader(ctx: ctx, width: CGFloat(width), topY: CGFloat(height - 18), title: "DockFlow", subtitle: "Закрытие по крестику полностью завершает процесс (⌘Q)")

        let cardW: CGFloat = 355
        let cardH: CGFloat = 320
        let cardY: CGFloat = 35

        let leftCardRect = CGRect(x: 22, y: cardY, width: cardW, height: cardH)
        let rightCardRect = CGRect(x: CGFloat(width) - cardW - 22, y: cardY, width: cardW, height: cardH)

        for (cardRect, isDockFlow) in [(leftCardRect, false), (rightCardRect, true)] {
            ctx.saveGState()
            let cPath = CGPath(roundedRect: cardRect, cornerWidth: 16, cornerHeight: 16, transform: nil)
            ctx.setFillColor(NSColor(red: 0.10, green: 0.11, blue: 0.15, alpha: 0.75).cgColor)
            ctx.addPath(cPath)
            ctx.fillPath()
            let strokeColor = isDockFlow ? NSColor(red: 0.25, green: 0.65, blue: 1.0, alpha: 0.35).cgColor : NSColor(white: 1.0, alpha: 0.09).cgColor
            ctx.setStrokeColor(strokeColor)
            ctx.setLineWidth(1.5)
            ctx.addPath(cPath)
            ctx.strokePath()
            ctx.restoreGState()
        }

        DrawUtils.drawText(ctx: ctx, text: "Стандартная macOS", point: CGPoint(x: leftCardRect.midX, y: leftCardRect.maxY - 24), font: NSFont.systemFont(ofSize: 13.5, weight: .bold), color: NSColor(red: 1.0, green: 0.45, blue: 0.45, alpha: 1.0), alignCenter: true)
        DrawUtils.drawText(ctx: ctx, text: "✨ С DockFlow", point: CGPoint(x: rightCardRect.midX, y: rightCardRect.maxY - 24), font: NSFont.systemFont(ofSize: 13.5, weight: .bold), color: NSColor(red: 0.35, green: 0.88, blue: 0.48, alpha: 1.0), alignCenter: true)

        let t = CGFloat(frame) / CGFloat(frameCount)

        let leftDockCenter = CGPoint(x: leftCardRect.midX, y: leftCardRect.minY + 70)
        let rightDockCenter = CGPoint(x: rightCardRect.midX, y: rightCardRect.minY + 70)

        let winW: CGFloat = 230
        let winH: CGFloat = 125
        let leftWinRect = CGRect(x: leftCardRect.midX - winW / 2, y: leftCardRect.minY + 125, width: winW, height: winH)
        let rightWinRect = CGRect(x: rightCardRect.midX - winW / 2, y: rightCardRect.minY + 125, width: winW, height: winH)

        let closeBtnTargetL = CGPoint(x: leftWinRect.minX + 16, y: leftWinRect.maxY - 14)
        let closeBtnTargetR = CGPoint(x: rightWinRect.minX + 16, y: rightWinRect.maxY - 14)

        var lCursorPos = CGPoint(x: leftWinRect.midX, y: leftWinRect.midY)
        var rCursorPos = CGPoint(x: rightWinRect.midX, y: rightWinRect.midY)
        var lHover = false, rHover = false
        var lClick = false, rClick = false
        var lWinAlpha: CGFloat = 1.0, rWinAlpha: CGFloat = 1.0
        let lRunning = [0, 1, 3]
        var rRunning = [0, 1, 3]

        if t < 0.25 {
            let p = t / 0.25
            lCursorPos = CGPoint(x: lerp(leftWinRect.midX, closeBtnTargetL.x, easeInOutCubic(p)),
                                 y: lerp(leftWinRect.midY, closeBtnTargetL.y, easeInOutCubic(p)))
            rCursorPos = CGPoint(x: lerp(rightWinRect.midX, closeBtnTargetR.x, easeInOutCubic(p)),
                                 y: lerp(rightWinRect.midY, closeBtnTargetR.y, easeInOutCubic(p)))
        } else if t < 0.35 {
            lCursorPos = closeBtnTargetL
            rCursorPos = closeBtnTargetR
            lHover = true
            rHover = true
        } else if t < 0.45 {
            lCursorPos = closeBtnTargetL
            rCursorPos = closeBtnTargetR
            lHover = true
            rHover = true
            lClick = (t >= 0.35 && t <= 0.40)
            rClick = (t >= 0.35 && t <= 0.40)
        } else if t < 0.65 {
            lCursorPos = CGPoint(x: closeBtnTargetL.x + 10, y: closeBtnTargetL.y - 15)
            rCursorPos = CGPoint(x: closeBtnTargetR.x + 10, y: closeBtnTargetR.y - 15)
            let p = (t - 0.45) / 0.20
            lWinAlpha = lerp(1.0, 0.0, p)
            rWinAlpha = lerp(1.0, 0.0, p)
            if t > 0.52 {
                rRunning = [0, 1]
            }
        } else {
            lCursorPos = CGPoint(x: closeBtnTargetL.x + 10, y: closeBtnTargetL.y - 15)
            rCursorPos = CGPoint(x: closeBtnTargetR.x + 10, y: closeBtnTargetR.y - 15)
            lWinAlpha = 0.0
            rWinAlpha = 0.0
            rRunning = [0, 1]
        }

        DrawUtils.drawWindow(ctx: ctx, rect: leftWinRect, title: "Safari — Браузер", scale: lWinAlpha > 0 ? 1.0 : 0.0, alpha: lWinAlpha, hoverClose: lHover)
        DrawUtils.drawDock(ctx: ctx, center: leftDockCenter, width: 280, activeIndex: -1, runningIndices: lRunning)
        DrawUtils.drawCursor(ctx: ctx, at: lCursorPos, isClicking: lClick)

        DrawUtils.drawWindow(ctx: ctx, rect: rightWinRect, title: "Safari — Браузер", scale: rWinAlpha > 0 ? 1.0 : 0.0, alpha: rWinAlpha, hoverClose: rHover)
        DrawUtils.drawDock(ctx: ctx, center: rightDockCenter, width: 280, activeIndex: -1, runningIndices: rRunning)
        DrawUtils.drawCursor(ctx: ctx, at: rCursorPos, isClicking: rClick)

        if t > 0.45 {
            let lBadgeRect = CGRect(x: leftCardRect.midX - 125, y: leftCardRect.minY + 16, width: 250, height: 28)
            ctx.saveGState()
            let lBPath = CGPath(roundedRect: lBadgeRect, cornerWidth: 7, cornerHeight: 7, transform: nil)
            ctx.setFillColor(NSColor(red: 0.35, green: 0.12, blue: 0.12, alpha: 0.8).cgColor)
            ctx.addPath(lBPath)
            ctx.fillPath()
            ctx.setStrokeColor(NSColor(red: 0.95, green: 0.35, blue: 0.35, alpha: 0.5).cgColor)
            ctx.setLineWidth(1)
            ctx.addPath(lBPath)
            ctx.strokePath()
            ctx.restoreGState()
            DrawUtils.drawText(ctx: ctx, text: "⚠️ Точка осталась • Процесс в фоне", point: CGPoint(x: lBadgeRect.midX, y: lBadgeRect.midY), font: NSFont.systemFont(ofSize: 11.5, weight: .medium), color: NSColor(red: 1.0, green: 0.65, blue: 0.65, alpha: 1.0), alignCenter: true)

            let rBadgeRect = CGRect(x: rightCardRect.midX - 125, y: rightCardRect.minY + 16, width: 250, height: 28)
            ctx.saveGState()
            let rBPath = CGPath(roundedRect: rBadgeRect, cornerWidth: 7, cornerHeight: 7, transform: nil)
            ctx.setFillColor(NSColor(red: 0.10, green: 0.30, blue: 0.16, alpha: 0.85).cgColor)
            ctx.addPath(rBPath)
            ctx.fillPath()
            ctx.setStrokeColor(NSColor(red: 0.35, green: 0.90, blue: 0.45, alpha: 0.5).cgColor)
            ctx.setLineWidth(1)
            ctx.addPath(rBPath)
            ctx.strokePath()
            ctx.restoreGState()
            DrawUtils.drawText(ctx: ctx, text: "✓ Завершено (⌘Q) • 0% CPU и RAM", point: CGPoint(x: rBadgeRect.midX, y: rBadgeRect.midY), font: NSFont.systemFont(ofSize: 11.5, weight: .bold), color: NSColor(red: 0.5, green: 1.0, blue: 0.6, alpha: 1.0), alignCenter: true)
        } else {
            DrawUtils.drawText(ctx: ctx, text: "Клик по красному крестику...", point: CGPoint(x: leftCardRect.midX, y: leftCardRect.minY + 22), font: NSFont.systemFont(ofSize: 12.5, weight: .medium), color: NSColor(white: 0.70, alpha: 1.0), alignCenter: true)
            DrawUtils.drawText(ctx: ctx, text: "Клик по красному крестику...", point: CGPoint(x: rightCardRect.midX, y: rightCardRect.minY + 22), font: NSFont.systemFont(ofSize: 12.5, weight: .medium), color: NSColor(white: 0.70, alpha: 1.0), alignCenter: true)
        }

        NSGraphicsContext.restoreGraphicsState()
        CGImageDestinationAddImage(dest, rep.cgImage!, frameProps as CFDictionary)
    }

    if CGImageDestinationFinalize(dest) {
        print("✅ Successfully generated \(outputPath)")
    } else {
        print("❌ Failed finalize \(outputPath)")
    }
}

// MARK: - Main Execution
let assetsDir = "/Users/minosssh1./.gemini/antigravity/scratch/DockMinimizer/assets"
generateDockMinimizeGIF(outputPath: "\(assetsDir)/demo_dock_minimize.gif")
generateQuitOnCloseGIF(outputPath: "\(assetsDir)/demo_quit_on_close.gif")
