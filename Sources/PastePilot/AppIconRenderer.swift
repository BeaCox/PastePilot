import AppKit

enum AppIconRenderer {
    static func icon(size: Int) -> NSImage {
        let s = CGFloat(size)
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: size, pixelsHigh: size,
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        draw(NSGraphicsContext.current!.cgContext, size: s)
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: NSSize(width: s, height: s))
        image.addRepresentation(rep)
        return image
    }

    private static func draw(_ ctx: CGContext, size s: CGFloat) {
        ctx.clear(CGRect(x: 0, y: 0, width: s, height: s))

        let m = s * 0.02
        let rect = CGRect(x: m, y: m, width: s - 2 * m, height: s - 2 * m)
        let r = s * 0.22
        let bgPath = CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)

        ctx.saveGState()
        ctx.addPath(bgPath)
        ctx.clip()
        let grad = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                CGColor(red: 0.231, green: 0.510, blue: 0.965, alpha: 1),
                CGColor(red: 0.357, green: 0.318, blue: 0.886, alpha: 1),
            ] as CFArray,
            locations: [0, 1]
        )!
        ctx.drawLinearGradient(
            grad,
            start: CGPoint(x: s * 0.2, y: 0),
            end: CGPoint(x: s * 0.8, y: s),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
        ctx.restoreGState()

        let ps = s * 0.44
        let cx = s * 0.5
        let cy = s * 0.5

        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: -s * 0.015),
            blur: s * 0.04,
            color: CGColor(red: 0, green: 0, blue: 0.2, alpha: 0.3)
        )
        ctx.translateBy(x: cx, y: cy)
        ctx.rotate(by: .pi * 0.12)

        ctx.beginPath()
        ctx.move(to: CGPoint(x: ps * 0.55, y: 0))
        ctx.addLine(to: CGPoint(x: -ps * 0.45, y: ps * 0.42))
        ctx.addLine(to: CGPoint(x: -ps * 0.12, y: ps * 0.02))
        ctx.closePath()
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
        ctx.fillPath()

        ctx.beginPath()
        ctx.move(to: CGPoint(x: ps * 0.55, y: 0))
        ctx.addLine(to: CGPoint(x: -ps * 0.12, y: -ps * 0.02))
        ctx.addLine(to: CGPoint(x: -ps * 0.45, y: -ps * 0.42))
        ctx.closePath()
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.75))
        ctx.fillPath()

        ctx.restoreGState()
    }
}
