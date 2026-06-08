#!/usr/bin/env swift

import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 3,
      let scale = Int(arguments[2]),
      scale == 1 || scale == 2 else {
    fputs("Usage: generate-dmg-background.swift <output.png> <scale: 1|2>\n", stderr)
    exit(1)
}

let logicalSize = NSSize(width: 600, height: 360)
let canvasSize = NSSize(
    width: logicalSize.width * CGFloat(scale),
    height: logicalSize.height * CGFloat(scale)
)
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvasSize.width),
    pixelsHigh: Int(canvasSize.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fputs("Failed to create DMG background canvas.\n", stderr)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fputs("Failed to create DMG background graphics context.\n", stderr)
    exit(1)
}
NSGraphicsContext.current = context
defer { NSGraphicsContext.restoreGraphicsState() }
context.cgContext.scaleBy(x: CGFloat(scale), y: CGFloat(scale))

let bounds = NSRect(origin: .zero, size: logicalSize)
let gradient = NSGradient(
    starting: NSColor(calibratedRed: 0.965, green: 0.978, blue: 0.995, alpha: 1),
    ending: NSColor(calibratedRed: 0.875, green: 0.925, blue: 0.985, alpha: 1)
)!
gradient.draw(in: bounds, angle: -90)

NSColor(calibratedRed: 0.05, green: 0.20, blue: 0.43, alpha: 0.055).setFill()
NSBezierPath(ovalIn: NSRect(x: -90, y: 195, width: 310, height: 310)).fill()
NSBezierPath(ovalIn: NSRect(x: 450, y: -120, width: 260, height: 260)).fill()

let titleStyle = NSMutableParagraphStyle()
titleStyle.alignment = .center

let title = NSAttributedString(
    string: "PastePilot",
    attributes: [
        .font: NSFont.systemFont(ofSize: 19, weight: .semibold),
        .foregroundColor: NSColor(calibratedRed: 0.035, green: 0.15, blue: 0.34, alpha: 1),
        .paragraphStyle: titleStyle
    ]
)
title.draw(in: NSRect(x: 0, y: 313, width: logicalSize.width, height: 27))

let subtitle = NSAttributedString(
    string: "Drag PastePilot to Applications",
    attributes: [
        .font: NSFont.systemFont(ofSize: 10, weight: .medium),
        .foregroundColor: NSColor(calibratedRed: 0.18, green: 0.30, blue: 0.47, alpha: 0.78),
        .paragraphStyle: titleStyle
    ]
)
subtitle.draw(in: NSRect(x: 0, y: 292, width: logicalSize.width, height: 17))

let arrowColor = NSColor(calibratedRed: 0.08, green: 0.31, blue: 0.64, alpha: 0.42)
arrowColor.setStroke()
let arrow = NSBezierPath()
arrow.lineWidth = 4.5
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
arrow.move(to: NSPoint(x: 252.5, y: 161))
arrow.line(to: NSPoint(x: 345, y: 161))
arrow.move(to: NSPoint(x: 324, y: 182))
arrow.line(to: NSPoint(x: 345, y: 161))
arrow.line(to: NSPoint(x: 324, y: 140))
arrow.stroke()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Failed to render DMG background.\n", stderr)
    exit(1)
}

try png.write(to: URL(fileURLWithPath: arguments[1]))
