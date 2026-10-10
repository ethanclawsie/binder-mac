#!/usr/bin/env swift
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon_Binder.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let size = CGFloat(px)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // 1. Outer squircle (Apple standard macOS app icon geometry)
    let inset = size * 0.09
    let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let squircle = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)

    // Drop shadow under squircle
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowOffset = NSSize(width: 0, height: -size * 0.02)
    shadow.shadowBlurRadius = size * 0.04
    NSGraphicsContext.saveGraphicsState()
    shadow.set()

    // Midnight obsidian / indigo gradient
    let bgGradient = NSGradient(
        starting: NSColor(calibratedRed: 0.14, green: 0.16, blue: 0.24, alpha: 1.0),
        ending: NSColor(calibratedRed: 0.07, green: 0.08, blue: 0.12, alpha: 1.0)
    )!
    bgGradient.draw(in: squircle, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // Inner rim light (fine bevel on squircle)
    NSGraphicsContext.saveGraphicsState()
    squircle.addClip()
    let innerRim = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
    NSColor(calibratedWhite: 1.0, alpha: 0.14).setStroke()
    innerRim.lineWidth = max(1.0, size * 0.006)
    innerRim.stroke()
    NSGraphicsContext.restoreGraphicsState()

    // 2. Tactile Keycap / Mouse Hybrid Base
    let keyW = size * 0.58
    let keyH = size * 0.58
    let keyX = (size - keyW) / 2
    let keyY = (size - keyH) / 2 - (size * 0.015)
    let keyRect = NSRect(x: keyX, y: keyY, width: keyW, height: keyH)
    let keyCorner = keyW * 0.20

    // Keycap 3D base bevel shadow
    let baseRect = NSRect(x: keyX, y: keyY - (size * 0.03), width: keyW, height: keyH + (size * 0.03))
    let basePath = NSBezierPath(roundedRect: baseRect, xRadius: keyCorner, yRadius: keyCorner)
    NSColor(calibratedRed: 0.04, green: 0.05, blue: 0.08, alpha: 0.85).setFill()
    basePath.fill()

    // Keycap top body
    let keyPath = NSBezierPath(roundedRect: keyRect, xRadius: keyCorner, yRadius: keyCorner)
    let keyGradient = NSGradient(
        colors: [
            NSColor(calibratedRed: 0.25, green: 0.28, blue: 0.40, alpha: 1.0),
            NSColor(calibratedRed: 0.17, green: 0.19, blue: 0.28, alpha: 1.0),
            NSColor(calibratedRed: 0.12, green: 0.13, blue: 0.20, alpha: 1.0)
        ],
        atLocations: [0.0, 0.6, 1.0],
        colorSpace: .deviceRGB
    )!
    keyGradient.draw(in: keyPath, angle: -90)

    // Keycap top highlight stroke
    NSGraphicsContext.saveGraphicsState()
    keyPath.addClip()
    let keyRim = NSBezierPath(roundedRect: keyRect.insetBy(dx: 0.5, dy: 0.5), xRadius: keyCorner, yRadius: keyCorner)
    NSColor(calibratedWhite: 1.0, alpha: 0.22).setStroke()
    keyRim.lineWidth = max(1.0, size * 0.008)
    keyRim.stroke()

    // 3. Mouse Click Division / Contour Line
    // Vertical seam through the top third representing mouse left/right button divide
    let seamPath = NSBezierPath()
    let midX = keyX + keyW * 0.5
    let seamTop = keyY + keyH
    let seamBottom = keyY + keyH * 0.45
    seamPath.move(to: NSPoint(x: midX, y: seamTop))
    seamPath.line(to: NSPoint(x: midX, y: seamBottom))
    seamPath.lineWidth = max(1.2, size * 0.008)
    NSColor(calibratedRed: 0.06, green: 0.07, blue: 0.11, alpha: 0.9).setStroke()
    seamPath.stroke()

    // Highlight beside seam
    let seamHL = NSBezierPath()
    seamHL.move(to: NSPoint(x: midX + max(1.0, size * 0.008), y: seamTop))
    seamHL.line(to: NSPoint(x: midX + max(1.0, size * 0.008), y: seamBottom))
    seamHL.lineWidth = max(0.8, size * 0.005)
    NSColor(calibratedWhite: 1.0, alpha: 0.15).setStroke()
    seamHL.stroke()

    // Mouse scroll wheel / tactile anchor pill in middle
    let pillW = size * 0.038
    let pillH = size * 0.10
    let pillRect = NSRect(x: midX - pillW / 2, y: seamBottom - pillH * 0.35, width: pillW, height: pillH)
    let pillPath = NSBezierPath(roundedRect: pillRect, xRadius: pillW * 0.5, yRadius: pillW * 0.5)
    let pillGrad = NSGradient(
        starting: NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.14, alpha: 1.0),
        ending: NSColor(calibratedRed: 0.18, green: 0.20, blue: 0.30, alpha: 1.0)
    )!
    pillGrad.draw(in: pillPath, angle: -90)
    NSColor(calibratedWhite: 1.0, alpha: 0.2).setStroke()
    pillPath.lineWidth = max(0.6, size * 0.004)
    pillPath.stroke()

    NSGraphicsContext.restoreGraphicsState()

    // 4. Center Symbol: Command (⌘) glyph cleanly embossed
    let symbolConfig = NSImage.SymbolConfiguration(pointSize: size * 0.24, weight: .bold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor.white]))

    if let cmdSymbol = NSImage(systemSymbolName: "command", accessibilityDescription: nil)?
        .withSymbolConfiguration(symbolConfig) {
        let s = cmdSymbol.size
        let glyphY = keyY + (keyH * 0.32) - (s.height * 0.5)
        let glyphX = (size - s.width) / 2

        // Soft glow / drop shadow for engraved depth
        let glyphShadow = NSShadow()
        glyphShadow.shadowColor = NSColor.black.withAlphaComponent(0.4)
        glyphShadow.shadowOffset = NSSize(width: 0, height: -size * 0.01)
        glyphShadow.shadowBlurRadius = size * 0.015

        NSGraphicsContext.saveGraphicsState()
        glyphShadow.set()
        cmdSymbol.draw(in: NSRect(x: glyphX, y: glyphY, width: s.width, height: s.height))
        NSGraphicsContext.restoreGraphicsState()
    }

    // 5. Electric Azure Accent Dot (representing live hardware trigger binding)
    let dotRadius = size * 0.018
    let dotCenter = NSPoint(x: keyX + keyW * 0.82, y: keyY + keyH * 0.82)
    let dotPath = NSBezierPath(ovalIn: NSRect(x: dotCenter.x - dotRadius, y: dotCenter.y - dotRadius, width: dotRadius * 2, height: dotRadius * 2))

    let dotGlow = NSShadow()
    dotGlow.shadowColor = NSColor(calibratedRed: 0.22, green: 0.74, blue: 0.97, alpha: 0.85)
    dotGlow.shadowBlurRadius = size * 0.03
    dotGlow.shadowOffset = .zero

    NSGraphicsContext.saveGraphicsState()
    dotGlow.set()
    NSColor(calibratedRed: 0.35, green: 0.82, blue: 1.0, alpha: 1.0).setFill()
    dotPath.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256] {
    try render(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}

let output = root.appendingPathComponent("Resources/AppIcon.icns")
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try task.run()
task.waitUntilExit()

print("✓ Generated \(output.path)")
