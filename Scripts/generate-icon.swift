#!/usr/bin/env swift

import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconsetDir = root.appendingPathComponent("Resources/AppIcon.iconset")
try FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

let entries: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for (name, px) in entries {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    drawIcon(NSGraphicsContext.current!.cgContext, size: s)
    NSGraphicsContext.restoreGraphicsState()

    try rep.representation(using: .png, properties: [:])!
        .write(to: iconsetDir.appendingPathComponent(name))
}

let icnsURL = root.appendingPathComponent("Resources/AppIcon.icns")
let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", iconsetDir.path, "-o", icnsURL.path]
try proc.run()
proc.waitUntilExit()
guard proc.terminationStatus == 0 else {
    fputs("iconutil failed\n", stderr)
    exit(1)
}
try FileManager.default.removeItem(at: iconsetDir)
print("Generated \(icnsURL.lastPathComponent)")

func drawIcon(_ ctx: CGContext, size s: CGFloat) {
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
