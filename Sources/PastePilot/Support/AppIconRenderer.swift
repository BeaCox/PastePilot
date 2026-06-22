import AppKit

enum MenuBarIconStyle: String, CaseIterable {
    case pastepilot
    case clipboard
    case paperplane

    var displayName: String {
        switch self {
        case .pastepilot: "PastePilot"
        case .clipboard: "Clipboard".localized
        case .paperplane: "Paperplane".localized
        }
    }

    var symbolName: String {
        switch self {
        case .pastepilot: "doc.on.clipboard"
        case .clipboard: "clipboard"
        case .paperplane: "paperplane"
        }
    }

    var previewImage: NSImage {
        AppIconRenderer.menuBarPreviewImage(style: self)
            ?? NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)!
    }
}

enum AppIconRenderer {
    static let menuBarPointSize = 18
    private static let pastePilotPickerPreviewPointSize = 15
    private static var menuBarImageCache: [String: NSImage] = [:]

    static func icon(size: Int) -> NSImage {
        let s = CGFloat(size)
        let rep = makeBitmapRep(pixels: size)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        drawAppIcon(NSGraphicsContext.current!.cgContext, size: s)
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: NSSize(width: s, height: s))
        image.addRepresentation(rep)
        return image
    }

    static func menuBarImage(style: MenuBarIconStyle, filled: Bool) -> NSImage? {
        let cacheKey = "\(style.rawValue)-\(filled)"
        if let image = menuBarImageCache[cacheKey] {
            return image
        }

        let image: NSImage?
        switch style {
        case .pastepilot:
            image = customMenuBarImage()
        case .clipboard:
            image = sfSymbol(filled ? "clipboard.fill" : "clipboard")
        case .paperplane:
            image = sfSymbol(filled ? "paperplane.fill" : "paperplane")
        }
        if let image {
            menuBarImageCache[cacheKey] = image
        }
        return image
    }

    static func menuBarPreviewImage(style: MenuBarIconStyle) -> NSImage? {
        guard let image = menuBarImage(style: style, filled: true) else {
            return nil
        }
        guard style == .pastepilot else {
            return image
        }
        let previewImage = image.copy() as? NSImage ?? image
        previewImage.size = NSSize(
            width: pastePilotPickerPreviewPointSize,
            height: pastePilotPickerPreviewPointSize
        )
        return previewImage
    }

    // MARK: - Menu bar icon (18pt@2x = 36px)

    private static func customMenuBarImage() -> NSImage {
        if let image = resourceImage(named: "MenuBarIconTemplate") {
            image.size = NSSize(width: menuBarPointSize, height: menuBarPointSize)
            image.isTemplate = true
            return image
        }

        let pt = menuBarPointSize
        let px = pt * 2
        let rep = makeBitmapRep(pixels: px)
        rep.size = NSSize(width: pt, height: pt)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let ctx = NSGraphicsContext.current!.cgContext
        let s = CGFloat(px)

        ctx.clear(CGRect(x: 0, y: 0, width: s, height: s))

        let color: CGColor = .black
        let boardW = s * 0.58
        let boardH = boardW * 1.16
        let boardX = (s - boardW) / 2
        let boardY = s * 0.08
        let strokeW = boardW * 0.14
        let cornerR = boardW * 0.18

        // Board outline via thick stroke
        let boardRect = CGRect(x: boardX, y: boardY, width: boardW, height: boardH)
        ctx.setStrokeColor(color)
        ctx.setLineWidth(strokeW)
        ctx.setLineJoin(.round)
        ctx.addPath(CGPath(roundedRect: boardRect, cornerWidth: cornerR, cornerHeight: cornerR, transform: nil))
        ctx.strokePath()

        // Clear behind clip tab so circle cutout shows background, not stroke
        let clipW = boardW * 0.46
        let clipH = boardH * 0.15
        let clipX = boardX + (boardW - clipW) / 2
        let clipY = boardY + boardH - clipH * 0.48

        ctx.saveGState()
        ctx.setBlendMode(.clear)
        ctx.fill(CGRect(x: clipX, y: boardY + boardH - strokeW / 2,
                         width: clipW, height: strokeW))
        ctx.restoreGState()

        // Clip tab with circle cutout
        let clipR = clipH * 0.35
        let circleD = clipH * 0.50
        let clipPath = CGMutablePath()
        clipPath.addRoundedRect(in: CGRect(x: clipX, y: clipY, width: clipW, height: clipH),
                                cornerWidth: clipR, cornerHeight: clipR)
        clipPath.addEllipse(in: CGRect(x: clipX + (clipW - circleD) / 2,
                                       y: clipY + (clipH - circleD) / 2,
                                       width: circleD, height: circleD))
        ctx.setFillColor(color)
        ctx.addPath(clipPath)
        ctx.fillPath(using: .evenOdd)

        // Text lines (2 for menu bar)
        let innerW = boardW - strokeW
        let lineX = boardX + strokeW / 2 + innerW * 0.14
        let lineH = boardH * 0.065
        let lineRad = lineH / 2
        ctx.setFillColor(color)

        for (i, lw) in ([0.62, 0.42] as [CGFloat]).enumerated() {
            let ly = boardY + boardH * 0.48 - CGFloat(i) * boardH * 0.19
            let lr = CGRect(x: lineX, y: ly, width: innerW * lw, height: lineH)
            ctx.addPath(CGPath(roundedRect: lr, cornerWidth: lineRad, cornerHeight: lineRad, transform: nil))
            ctx.fillPath()
        }

        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: NSSize(width: pt, height: pt))
        image.addRepresentation(rep)
        image.isTemplate = true
        return image
    }

    private static func sfSymbol(_ name: String) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        return NSImage(
            systemSymbolName: name,
            accessibilityDescription: "PastePilot"
        )?.withSymbolConfiguration(config)
    }

    // MARK: - App icon

    static func drawAppIcon(_ ctx: CGContext, size s: CGFloat) {
        ctx.clear(CGRect(x: 0, y: 0, width: s, height: s))

        // Background
        let m = s * 0.02
        let bgRect = CGRect(x: m, y: m, width: s - 2 * m, height: s - 2 * m)
        let bgR = s * 0.22
        let bgPath = CGPath(roundedRect: bgRect, cornerWidth: bgR, cornerHeight: bgR, transform: nil)

        ctx.saveGState()
        ctx.addPath(bgPath)
        ctx.clip()
        let grad = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                CGColor(red: 0.133, green: 0.827, blue: 0.933, alpha: 1),
                CGColor(red: 0.388, green: 0.400, blue: 0.945, alpha: 1),
            ] as CFArray,
            locations: [0, 1]
        )!
        ctx.drawLinearGradient(
            grad,
            start: CGPoint(x: 0, y: s),
            end: CGPoint(x: s, y: 0),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
        ctx.restoreGState()

        let white = CGColor(red: 1, green: 1, blue: 1, alpha: 0.95)
        let strokeW = s * 0.04
        let boardW = s * 0.48
        let boardH = boardW * 1.16
        let boardX = (s - boardW) / 2
        let boardY = s * 0.15
        let cornerR = boardW * 0.17

        // Board outline with shadow
        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: -s * 0.008),
            blur: s * 0.02,
            color: CGColor(red: 0, green: 0, blue: 0.15, alpha: 0.18)
        )
        let boardRect = CGRect(x: boardX, y: boardY, width: boardW, height: boardH)
        ctx.setStrokeColor(white)
        ctx.setLineWidth(strokeW)
        ctx.setLineJoin(.round)
        ctx.addPath(CGPath(roundedRect: boardRect, cornerWidth: cornerR, cornerHeight: cornerR, transform: nil))
        ctx.strokePath()
        ctx.restoreGState()

        // Clip tab
        let clipW = boardW * 0.44
        let clipH = boardH * 0.13
        let clipX = boardX + (boardW - clipW) / 2
        let clipY = boardY + boardH - clipH * 0.48
        let clipR = clipH * 0.32
        let circleD = clipH * 0.48

        let clipPath = CGMutablePath()
        clipPath.addRoundedRect(in: CGRect(x: clipX, y: clipY, width: clipW, height: clipH),
                                cornerWidth: clipR, cornerHeight: clipR)
        clipPath.addEllipse(in: CGRect(x: clipX + (clipW - circleD) / 2,
                                       y: clipY + (clipH - circleD) / 2,
                                       width: circleD, height: circleD))
        ctx.setFillColor(white)
        ctx.addPath(clipPath)
        ctx.fillPath(using: .evenOdd)

        // Text lines (3 for app icon)
        let innerW = boardW - strokeW
        let lineX = boardX + strokeW / 2 + innerW * 0.12
        let lineH = boardH * 0.048
        let lineRad = lineH / 2
        ctx.setFillColor(white)

        for (i, lw) in ([0.66, 0.54, 0.40] as [CGFloat]).enumerated() {
            let ly = boardY + boardH * 0.52 - CGFloat(i) * boardH * 0.14
            let lr = CGRect(x: lineX, y: ly, width: innerW * lw, height: lineH)
            ctx.addPath(CGPath(roundedRect: lr, cornerWidth: lineRad, cornerHeight: lineRad, transform: nil))
            ctx.fillPath()
        }

        // Sparkle
        let sparkleOutR = s * 0.055
        let sparkleInR = sparkleOutR * 0.22
        let sparkleCenter = CGPoint(
            x: boardX + boardW + sparkleOutR * 0.08,
            y: boardY - sparkleOutR * 0.05
        )

        // Subtle glow
        ctx.saveGState()
        let glowGrad = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                CGColor(red: 0.5, green: 0.85, blue: 1.0, alpha: 0.3),
                CGColor(red: 0.5, green: 0.85, blue: 1.0, alpha: 0),
            ] as CFArray,
            locations: [0, 1]
        )!
        ctx.drawRadialGradient(
            glowGrad,
            startCenter: sparkleCenter, startRadius: 0,
            endCenter: sparkleCenter, endRadius: sparkleOutR * 2.5,
            options: []
        )
        ctx.restoreGState()

        // Sparkle shape (light blue accent)
        ctx.setFillColor(CGColor(red: 0.7, green: 0.92, blue: 1.0, alpha: 0.95))
        ctx.addPath(makeSparkle(center: sparkleCenter, outerR: sparkleOutR, innerR: sparkleInR))
        ctx.fillPath()
    }

    // MARK: - Helpers

    private static func resourceImage(named name: String) -> NSImage? {
        let fileName = "\(name).png"
        let candidates = [
            Bundle.main.url(forResource: name, withExtension: "png"),
            Bundle.main.resourceURL?.appendingPathComponent(fileName),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Resources")
                .appendingPathComponent(fileName),
        ]

        for url in candidates.compactMap({ $0 }) {
            if let image = NSImage(contentsOf: url) {
                return image
            }
        }
        return nil
    }

    private static func makeSparkle(center: CGPoint, outerR: CGFloat, innerR: CGFloat) -> CGPath {
        let path = CGMutablePath()
        for i in 0..<8 {
            let angle = CGFloat(i) * .pi / 4 - .pi / 2
            let r = i % 2 == 0 ? outerR : innerR
            let p = CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }

    private static func makeBitmapRep(pixels: Int) -> NSBitmapImageRep {
        NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        )!
    }
}
