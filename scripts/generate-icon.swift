#!/usr/bin/env swift
// Generates ClaudeBar app icon — a Claude-inspired starburst in teal/green
import AppKit
import CoreGraphics

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    let center = CGPoint(x: size / 2, y: size / 2)
    let scale = size / 512.0

    // Background: rounded rectangle with slight gradient
    let cornerRadius = size * 0.22
    let bgRect = CGRect(x: 0, y: 0, width: size, height: size)
    let bgPath = CGPath(roundedRect: bgRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

    // Gradient background — dark teal to slightly lighter teal
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let gradientColors = [
        CGColor(red: 0.05, green: 0.45, blue: 0.52, alpha: 1.0),  // darker teal
        CGColor(red: 0.10, green: 0.58, blue: 0.65, alpha: 1.0),  // lighter teal
    ] as CFArray
    let gradient = CGGradient(colorsSpace: colorSpace, colors: gradientColors, locations: [0.0, 1.0])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])
    ctx.restoreGState()

    // Draw starburst — 8 rounded capsule "petals" rotated around center
    let petalCount = 8
    let petalLength = 130.0 * scale    // half-length from center
    let petalWidth = 38.0 * scale
    let innerRadius = 42.0 * scale     // gap in the center

    ctx.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.95))

    for i in 0..<petalCount {
        let angle = Double(i) * (.pi / Double(petalCount))

        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: angle)

        // Draw capsule (rounded rect) from innerRadius outward
        let capsuleRect = CGRect(
            x: -petalWidth / 2,
            y: innerRadius,
            width: petalWidth,
            height: petalLength - innerRadius
        )
        let capsulePath = CGPath(roundedRect: capsuleRect, cornerWidth: petalWidth / 2, cornerHeight: petalWidth / 2, transform: nil)
        ctx.addPath(capsulePath)
        ctx.fillPath()

        // Mirror on other side
        let capsuleRect2 = CGRect(
            x: -petalWidth / 2,
            y: -(petalLength),
            width: petalWidth,
            height: petalLength - innerRadius
        )
        let capsulePath2 = CGPath(roundedRect: capsuleRect2, cornerWidth: petalWidth / 2, cornerHeight: petalWidth / 2, transform: nil)
        ctx.addPath(capsulePath2)
        ctx.fillPath()

        ctx.restoreGState()
    }

    // Center circle
    let dotRadius = 28.0 * scale
    let dotRect = CGRect(x: center.x - dotRadius, y: center.y - dotRadius, width: dotRadius * 2, height: dotRadius * 2)
    ctx.fillEllipse(in: dotRect)

    image.unlockFocus()
    return image
}

func savePNG(_ image: NSImage, to path: String) {
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        print("Failed to create PNG for \(path)")
        return
    }
    try! pngData.write(to: URL(fileURLWithPath: path))
}

// Generate iconset
let iconsetDir = ".build/ClaudeBar.iconset"
try? FileManager.default.removeItem(atPath: iconsetDir)
try! FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

let sizes: [(name: String, size: CGFloat)] = [
    ("icon_16x16", 16),
    ("icon_16x16@2x", 32),
    ("icon_32x32", 32),
    ("icon_32x32@2x", 64),
    ("icon_128x128", 128),
    ("icon_128x128@2x", 256),
    ("icon_256x256", 256),
    ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
    ("icon_512x512@2x", 1024),
]

for entry in sizes {
    let image = drawIcon(size: entry.size)
    savePNG(image, to: "\(iconsetDir)/\(entry.name).png")
    print("Generated \(entry.name).png (\(Int(entry.size))x\(Int(entry.size)))")
}

print("Iconset created at \(iconsetDir)")
print("Run: iconutil -c icns \(iconsetDir) -o Sources/Resources/AppIcon.icns")
