import AppKit
import Foundation

func generateAppIcon() {
    let size = CGSize(width: 1024, height: 1024)
    let img = NSImage(size: size)
    img.lockFocus()

    guard let ctx = NSGraphicsContext.current?.cgContext else {
        print("Failed to get CGContext")
        exit(1)
    }

    // Shadow behind the squircle
    ctx.saveGState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowOffset = NSSize(width: 0, height: -20)
    shadow.shadowBlurRadius = 35
    shadow.set()

    // macOS squircle / rounded rectangle
    let rect = CGRect(x: 90, y: 90, width: 844, height: 844)
    let squirclePath = CGPath(roundedRect: rect, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.addPath(squirclePath)
    ctx.setFillColor(NSColor(red: 0.11, green: 0.12, blue: 0.16, alpha: 1.0).cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // Clip to squircle for inner drawing
    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.clip()

    // Gradient background: Dark obsidian to deep warm dark slate
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bgColors = [
        NSColor(red: 0.14, green: 0.16, blue: 0.22, alpha: 1.0).cgColor,
        NSColor(red: 0.08, green: 0.09, blue: 0.12, alpha: 1.0).cgColor
    ] as CFArray
    if let bgGradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(bgGradient, start: CGPoint(x: 512, y: 934), end: CGPoint(x: 512, y: 90), options: [])
    }

    // Inner subtle glow border
    ctx.setLineWidth(10)
    ctx.setStrokeColor(NSColor(red: 0.85, green: 0.47, blue: 0.34, alpha: 0.45).cgColor)
    ctx.addPath(squirclePath)
    ctx.strokePath()

    let center = CGPoint(x: 512, y: 512)

    // Outer Gauge Arc: 7-Day Limit (Anthropic Terracotta #D97757)
    let radius7d: CGFloat = 280
    ctx.setLineWidth(32)
    ctx.setLineCap(.round)

    // 7d background track
    ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.08).cgColor)
    ctx.addArc(center: center, radius: radius7d, startAngle: 0.8 * .pi, endAngle: 2.2 * .pi, clockwise: false)
    ctx.strokePath()

    // 7d active meter (~70% filled)
    ctx.setStrokeColor(NSColor(red: 0.85, green: 0.47, blue: 0.34, alpha: 1.0).cgColor)
    ctx.addArc(center: center, radius: radius7d, startAngle: 0.8 * .pi, endAngle: 1.82 * .pi, clockwise: false)
    ctx.strokePath()

    // Inner Gauge Arc: 5-Hour Session (Emerald #34D399)
    let radius5h: CGFloat = 210
    ctx.setLineWidth(26)

    // 5h background track
    ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.08).cgColor)
    ctx.addArc(center: center, radius: radius5h, startAngle: 0.8 * .pi, endAngle: 2.2 * .pi, clockwise: false)
    ctx.strokePath()

    // 5h active meter (~45% filled)
    ctx.setStrokeColor(NSColor(red: 0.20, green: 0.82, blue: 0.60, alpha: 1.0).cgColor)
    ctx.addArc(center: center, radius: radius5h, startAngle: 0.8 * .pi, endAngle: 1.45 * .pi, clockwise: false)
    ctx.strokePath()

    // Center Claude 8-point geometric Star / Spark
    let sparkSize: CGFloat = 78
    let sparkPath = CGMutablePath()
    for i in 0..<8 {
        let angle = CGFloat(i) * (.pi / 4.0)
        let outerP = CGPoint(x: center.x + cos(angle) * sparkSize, y: center.y + sin(angle) * sparkSize)
        let midAngle = angle + (.pi / 8.0)
        let innerP = CGPoint(x: center.x + cos(midAngle) * (sparkSize * 0.42), y: center.y + sin(midAngle) * (sparkSize * 0.42))
        if i == 0 { sparkPath.move(to: outerP) } else { sparkPath.addLine(to: outerP) }
        sparkPath.addLine(to: innerP)
    }
    sparkPath.closeSubpath()

    // Fill Spark with warm Claude gradient
    let sparkColors = [
        NSColor(red: 0.98, green: 0.68, blue: 0.52, alpha: 1.0).cgColor,
        NSColor(red: 0.85, green: 0.47, blue: 0.34, alpha: 1.0).cgColor
    ] as CFArray
    if let sparkGradient = CGGradient(colorsSpace: colorSpace, colors: sparkColors, locations: [0.0, 1.0]) {
        ctx.saveGState()
        ctx.addPath(sparkPath)
        ctx.clip()
        ctx.drawLinearGradient(sparkGradient, start: CGPoint(x: center.x, y: center.y + sparkSize), end: CGPoint(x: center.x, y: center.y - sparkSize), options: [])
        ctx.restoreGState()
    }

    ctx.restoreGState()
    img.unlockFocus()

    guard let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        print("Failed to convert image to PNG")
        exit(1)
    }

    let outDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("AppIcon.iconset")
    try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

    let masterPng = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("AppIcon_1024.png")
    try! png.write(to: masterPng)
    print("Master 1024x1024 icon saved to \(masterPng.path)")

    // Generate resolutions
    let sizes: [(Int, String)] = [
        (16, "icon_16x16.png"),
        (32, "icon_16x16@2x.png"),
        (32, "icon_32x32.png"),
        (64, "icon_32x32@2x.png"),
        (128, "icon_128x128.png"),
        (256, "icon_128x128@2x.png"),
        (256, "icon_256x256.png"),
        (512, "icon_256x256@2x.png"),
        (512, "icon_512x512.png"),
        (1024, "icon_512x512@2x.png")
    ]

    for (dim, name) in sizes {
        let dest = outDir.appendingPathComponent(name)
        let task = Process()
        task.launchPath = "/usr/bin/sips"
        task.arguments = ["-z", "\(dim)", "\(dim)", masterPng.path, "--out", dest.path]
        task.launch()
        task.waitUntilExit()
    }

    let iconutilTask = Process()
    iconutilTask.launchPath = "/usr/bin/iconutil"
    iconutilTask.arguments = ["-c", "icns", outDir.path, "-o", "AppIcon.icns"]
    iconutilTask.launch()
    iconutilTask.waitUntilExit()

    print("AppIcon.icns successfully generated!")
}

generateAppIcon()
