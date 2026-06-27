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
            ?? NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
            ?? NSImage(size: NSSize(
                width: AppIconRenderer.menuBarPointSize,
                height: AppIconRenderer.menuBarPointSize
            ))
    }
}

enum AppIconRenderer {
    static let menuBarPointSize = 18
    private static let pastePilotPickerPreviewPointSize = 15
    private static var menuBarImageCache: [String: NSImage] = [:]

    static func icon(size: Int) -> NSImage {
        guard let image = resourceImage(named: "AppIcon", extensions: ["icns"])
            ?? resourceImage(named: "AppIconSource")
            ?? NSApplication.shared.applicationIconImage else {
            return NSImage(size: NSSize(width: size, height: size))
        }
        let icon = image.copy() as? NSImage ?? image
        icon.size = NSSize(width: size, height: size)
        return icon
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
        guard let rep = makeBitmapRep(pixels: px),
              let graphicsContext = NSGraphicsContext(bitmapImageRep: rep) else {
            return fallbackMenuBarImage()
        }
        rep.size = NSSize(width: pt, height: pt)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        let ctx = graphicsContext.cgContext
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

    private static func fallbackMenuBarImage() -> NSImage {
        let image = sfSymbol("doc.on.clipboard")
            ?? NSImage(size: NSSize(
                width: menuBarPointSize,
                height: menuBarPointSize
            ))
        image.size = NSSize(width: menuBarPointSize, height: menuBarPointSize)
        image.isTemplate = true
        return image
    }

    // MARK: - Helpers

    private static func resourceImage(named name: String, extensions: [String] = ["png"]) -> NSImage? {
        for ext in extensions {
            let fileName = "\(name).\(ext)"
            let candidates = [
                Bundle.main.url(forResource: name, withExtension: ext),
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
        }
        return nil
    }

    private static func makeBitmapRep(pixels: Int) -> NSBitmapImageRep? {
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
