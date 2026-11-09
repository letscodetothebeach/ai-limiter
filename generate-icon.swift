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

    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    let colorSpace = CGColorSpaceCreateDeviceRGB()

    // MARK: - 1. macOS Squircle Drop Shadow
    ctx.saveGState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
    shadow.shadowOffset = NSSize(width: 0, height: -22)
    shadow.shadowBlurRadius = 36
    shadow.set()

    let squircleRect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let squircleCornerRadius: CGFloat = 185
    let squirclePath = CGPath(roundedRect: squircleRect, cornerWidth: squircleCornerRadius, cornerHeight: squircleCornerRadius, transform: nil)
    ctx.addPath(squirclePath)
    ctx.setFillColor(NSColor(red: 0.08, green: 0.09, blue: 0.13, alpha: 1.0).cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // MARK: - 2. Squircle Clipping & Base Gradient
    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.clip()

    // Background: Luxurious dark slate/sapphire obsidian gradient
    let bgColors = [
        NSColor(red: 0.13, green: 0.15, blue: 0.22, alpha: 1.0).cgColor,
        NSColor(red: 0.07, green: 0.08, blue: 0.11, alpha: 1.0).cgColor
    ] as CFArray
    if let bgGradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(bgGradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    }

    let center = CGPoint(x: 512, y: 518)

    // Ambient radial backlight behind the gauge
    let ambientColors = [
        NSColor(red: 0.90, green: 0.48, blue: 0.32, alpha: 0.20).cgColor,
        NSColor(red: 0.14, green: 0.18, blue: 0.28, alpha: 0.06).cgColor,
        NSColor(white: 0.0, alpha: 0.0).cgColor
    ] as CFArray
    if let ambientGrad = CGGradient(colorsSpace: colorSpace, colors: ambientColors, locations: [0.0, 0.55, 1.0]) {
        ctx.drawRadialGradient(ambientGrad, startCenter: CGPoint(x: center.x, y: center.y + 20), startRadius: 30, endCenter: center, endRadius: 390, options: [])
    }

    // MARK: - 3. Recessed Instrument Dial Plate
    let dialRadius: CGFloat = 345
    let dialRect = CGRect(x: center.x - dialRadius, y: center.y - dialRadius, width: dialRadius * 2, height: dialRadius * 2)

    // Dark dial plate with subtle top-to-bottom metallic gradient
    ctx.saveGState()
    let dialColors = [
        NSColor(red: 0.11, green: 0.12, blue: 0.17, alpha: 1.0).cgColor,
        NSColor(red: 0.05, green: 0.06, blue: 0.09, alpha: 1.0).cgColor
    ] as CFArray
    if let dialGrad = CGGradient(colorsSpace: colorSpace, colors: dialColors, locations: [0.0, 1.0]) {
        ctx.addEllipse(in: dialRect)
        ctx.clip()
        ctx.drawLinearGradient(dialGrad, start: CGPoint(x: 512, y: center.y + dialRadius), end: CGPoint(x: 512, y: center.y - dialRadius), options: [])
    }
    ctx.restoreGState()

    // Outer Bezel Rim
    ctx.setLineWidth(3.0)
    ctx.setStrokeColor(NSColor(red: 0.35, green: 0.40, blue: 0.52, alpha: 0.45).cgColor)
    ctx.addEllipse(in: dialRect)
    ctx.strokePath()

    // Subtle concentric grooves
    for grooveRadius in [CGFloat(341), CGFloat(256), CGFloat(168)] {
        let r = CGRect(x: center.x - grooveRadius, y: center.y - grooveRadius, width: grooveRadius * 2, height: grooveRadius * 2)
        ctx.setLineWidth(1.0)
        ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.06).cgColor)
        ctx.addEllipse(in: r)
        ctx.strokePath()
    }

    // MARK: - 4. Precision Gauge Angles
    // Standard Gauge orientation: sweeping UP over the top!
    // Start at bottom-left: 215° (in radians = 215 * .pi / 180)
    // End at bottom-right: -35° (in radians = -35 * .pi / 180)
    // Total sweep: 250 degrees (clockwise: true decreases angle through 180 -> 90 -> 0 -> -35)
    let startDeg: CGFloat = 215
    let endDeg: CGFloat = -35
    let totalSweepDeg: CGFloat = startDeg - endDeg // 250°

    let startRad = startDeg * .pi / 180.0
    let endRad = endDeg * .pi / 180.0

    // Dial Ticks: 40 ticks spaced around the 250° gauge arc
    let tickCount = 36
    for i in 0...tickCount {
        let t = CGFloat(i) / CGFloat(tickCount)
        let deg = startDeg - t * totalSweepDeg
        let rad = deg * .pi / 180.0

        let isMajor = (i % 6 == 0)
        let innerR: CGFloat = isMajor ? 318 : 326
        let outerR: CGFloat = 336

        let p1 = CGPoint(x: center.x + cos(rad) * innerR, y: center.y + sin(rad) * innerR)
        let p2 = CGPoint(x: center.x + cos(rad) * outerR, y: center.y + sin(rad) * outerR)

        ctx.setLineWidth(isMajor ? 3.0 : 1.5)
        ctx.setLineCap(.round)
        ctx.setStrokeColor(isMajor ? NSColor(red: 0.95, green: 0.72, blue: 0.56, alpha: 0.7).cgColor : NSColor(white: 1.0, alpha: 0.16).cgColor)
        ctx.strokeLineSegments(between: [p1, p2])
    }

    // MARK: - 5. Outer Quota Arc (7-Day Limit: Terracotta / Amber-Coral)
    let radius7d: CGFloat = 286
    let fillRatio7d: CGFloat = 0.72 // 72% filled
    let activeEndDeg7d = startDeg - (totalSweepDeg * fillRatio7d)
    let activeEndRad7d = activeEndDeg7d * .pi / 180.0

    ctx.setLineCap(.round)

    // 7d Background track
    ctx.setLineWidth(24)
    ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.08).cgColor)
    ctx.addArc(center: center, radius: radius7d, startAngle: startRad, endAngle: endRad, clockwise: true)
    ctx.strokePath()

    // 7d Diffuse luminous glow pass underneath
    ctx.saveGState()
    let glow7d = NSShadow()
    glow7d.shadowColor = NSColor(red: 0.95, green: 0.48, blue: 0.32, alpha: 0.85)
    glow7d.shadowOffset = .zero
    glow7d.shadowBlurRadius = 18
    glow7d.set()
    ctx.setLineWidth(22)
    ctx.setStrokeColor(NSColor(red: 0.95, green: 0.50, blue: 0.34, alpha: 0.7).cgColor)
    ctx.addArc(center: center, radius: radius7d, startAngle: startRad, endAngle: activeEndRad7d, clockwise: true)
    ctx.strokePath()
    ctx.restoreGState()

    // 7d Foreground active arc
    ctx.setLineWidth(22)
    ctx.setStrokeColor(NSColor(red: 0.96, green: 0.52, blue: 0.36, alpha: 1.0).cgColor)
    ctx.addArc(center: center, radius: radius7d, startAngle: startRad, endAngle: activeEndRad7d, clockwise: true)
    ctx.strokePath()

    // 7d Glowing Tip Bead
    let tip7d = CGPoint(x: center.x + cos(activeEndRad7d) * radius7d, y: center.y + sin(activeEndRad7d) * radius7d)
    ctx.saveGState()
    let beadGlow7d = NSShadow()
    beadGlow7d.shadowColor = NSColor(red: 1.0, green: 0.75, blue: 0.5, alpha: 0.95)
    beadGlow7d.shadowOffset = .zero
    beadGlow7d.shadowBlurRadius = 14
    beadGlow7d.set()
    ctx.setFillColor(NSColor(red: 1.0, green: 0.92, blue: 0.82, alpha: 1.0).cgColor)
    ctx.fillEllipse(in: CGRect(x: tip7d.x - 7, y: tip7d.y - 7, width: 14, height: 14))
    ctx.restoreGState()

    // MARK: - 6. Inner Session Arc (5-Hour Session: Vivid Emerald / Cyan)
    let radius5h: CGFloat = 224
    let fillRatio5h: CGFloat = 0.48 // 48% filled
    let activeEndDeg5h = startDeg - (totalSweepDeg * fillRatio5h)
    let activeEndRad5h = activeEndDeg5h * .pi / 180.0

    // 5h Background track
    ctx.setLineWidth(18)
    ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.08).cgColor)
    ctx.addArc(center: center, radius: radius5h, startAngle: startRad, endAngle: endRad, clockwise: true)
    ctx.strokePath()

    // 5h Diffuse glow pass underneath
    ctx.saveGState()
    let glow5h = NSShadow()
    glow5h.shadowColor = NSColor(red: 0.18, green: 0.86, blue: 0.65, alpha: 0.85)
    glow5h.shadowOffset = .zero
    glow5h.shadowBlurRadius = 16
    glow5h.set()
    ctx.setLineWidth(16)
    ctx.setStrokeColor(NSColor(red: 0.18, green: 0.86, blue: 0.65, alpha: 0.75).cgColor)
    ctx.addArc(center: center, radius: radius5h, startAngle: startRad, endAngle: activeEndRad5h, clockwise: true)
    ctx.strokePath()
    ctx.restoreGState()

    // 5h Foreground active arc
    ctx.setLineWidth(16)
    ctx.setStrokeColor(NSColor(red: 0.22, green: 0.90, blue: 0.68, alpha: 1.0).cgColor)
    ctx.addArc(center: center, radius: radius5h, startAngle: startRad, endAngle: activeEndRad5h, clockwise: true)
    ctx.strokePath()

    // 5h Glowing Tip Bead
    let tip5h = CGPoint(x: center.x + cos(activeEndRad5h) * radius5h, y: center.y + sin(activeEndRad5h) * radius5h)
    ctx.saveGState()
    let beadGlow5h = NSShadow()
    beadGlow5h.shadowColor = NSColor(red: 0.45, green: 1.0, blue: 0.82, alpha: 0.95)
    beadGlow5h.shadowOffset = .zero
    beadGlow5h.shadowBlurRadius = 12
    beadGlow5h.set()
    ctx.setFillColor(NSColor(red: 0.85, green: 1.0, blue: 0.94, alpha: 1.0).cgColor)
    ctx.fillEllipse(in: CGRect(x: tip5h.x - 6, y: tip5h.y - 6, width: 12, height: 12))
    ctx.restoreGState()

    // MARK: - 7. Center Core Housing & Refined Curved Claude AI Spark
    let centerHousingRadius: CGFloat = 152
    let centerRect = CGRect(x: center.x - centerHousingRadius, y: center.y - centerHousingRadius, width: centerHousingRadius * 2, height: centerHousingRadius * 2)

    // Center Core Background Plate
    ctx.saveGState()
    let centerColors = [
        NSColor(red: 0.14, green: 0.16, blue: 0.24, alpha: 1.0).cgColor,
        NSColor(red: 0.07, green: 0.08, blue: 0.12, alpha: 1.0).cgColor
    ] as CFArray
    if let centerGrad = CGGradient(colorsSpace: colorSpace, colors: centerColors, locations: [0.0, 1.0]) {
        ctx.addEllipse(in: centerRect)
        ctx.clip()
        ctx.drawLinearGradient(centerGrad, start: CGPoint(x: 512, y: center.y + centerHousingRadius), end: CGPoint(x: 512, y: center.y - centerHousingRadius), options: [])
    }
    ctx.restoreGState()

    // Center Lens Bezel Ring
    ctx.setLineWidth(2.5)
    ctx.setStrokeColor(NSColor(red: 0.45, green: 0.52, blue: 0.68, alpha: 0.45).cgColor)
    ctx.addEllipse(in: centerRect)
    ctx.strokePath()

    // Center Core Radial Ambient Glow
    let coreGlowColors = [
        NSColor(red: 0.96, green: 0.56, blue: 0.36, alpha: 0.36).cgColor,
        NSColor(red: 0.90, green: 0.45, blue: 0.30, alpha: 0.10).cgColor,
        NSColor(white: 0.0, alpha: 0.0).cgColor
    ] as CFArray
    if let coreGrad = CGGradient(colorsSpace: colorSpace, colors: coreGlowColors, locations: [0.0, 0.6, 1.0]) {
        ctx.drawRadialGradient(coreGrad, startCenter: center, startRadius: 10, endCenter: center, endRadius: 148, options: [])
    }

    // Organic Claude Spark: 4 primary axial petals (88px) & 4 secondary diagonal petals (52px)
    let primaryR: CGFloat = 88
    let secondaryR: CGFloat = 52
    let waistR: CGFloat = 24

    let sparkPath = CGMutablePath()
    let petalCount = 8

    for i in 0..<petalCount {
        let isAxial = (i % 2 == 0)
        let peakR = isAxial ? primaryR : secondaryR
        let peakAngle = CGFloat(i) * (.pi / 4.0)

        let prevWaistAngle = peakAngle - (.pi / 8.0)
        let nextWaistAngle = peakAngle + (.pi / 8.0)

        let waistStart = CGPoint(x: center.x + cos(prevWaistAngle) * waistR, y: center.y + sin(prevWaistAngle) * waistR)
        let tipPoint = CGPoint(x: center.x + cos(peakAngle) * peakR, y: center.y + sin(peakAngle) * peakR)
        let waistEnd = CGPoint(x: center.x + cos(nextWaistAngle) * waistR, y: center.y + sin(nextWaistAngle) * waistR)

        // Control points for smooth organic curvature
        let ctrlOut = CGPoint(x: center.x + cos(prevWaistAngle + 0.15) * (peakR * 0.58),
                              y: center.y + sin(prevWaistAngle + 0.15) * (peakR * 0.58))
        let ctrlIn = CGPoint(x: center.x + cos(nextWaistAngle - 0.15) * (peakR * 0.58),
                             y: center.y + sin(nextWaistAngle - 0.15) * (peakR * 0.58))

        if i == 0 {
            sparkPath.move(to: waistStart)
        }
        sparkPath.addQuadCurve(to: tipPoint, control: ctrlOut)
        sparkPath.addQuadCurve(to: waistEnd, control: ctrlIn)
    }
    sparkPath.closeSubpath()

    // Spark Drop Shadow
    ctx.saveGState()
    let sparkShadow = NSShadow()
    sparkShadow.shadowColor = NSColor(red: 0.95, green: 0.50, blue: 0.30, alpha: 0.85)
    sparkShadow.shadowOffset = NSSize(width: 0, height: -2)
    sparkShadow.shadowBlurRadius = 26
    sparkShadow.set()

    // Spark Multi-Stop Radial Radiant Gradient
    let sparkColors = [
        NSColor(red: 1.0, green: 0.95, blue: 0.86, alpha: 1.0).cgColor,  // Luminous ivory-gold core
        NSColor(red: 0.98, green: 0.65, blue: 0.42, alpha: 1.0).cgColor,  // Warm peach amber
        NSColor(red: 0.88, green: 0.44, blue: 0.28, alpha: 1.0).cgColor   // Iconic Claude Terracotta
    ] as CFArray

    if let sparkGrad = CGGradient(colorsSpace: colorSpace, colors: sparkColors, locations: [0.0, 0.45, 1.0]) {
        ctx.addPath(sparkPath)
        ctx.clip()
        ctx.drawRadialGradient(sparkGrad, startCenter: center, startRadius: 4, endCenter: center, endRadius: primaryR, options: [])
    }
    ctx.restoreGState()

    // Specular Glint in center
    ctx.saveGState()
    let glintShadow = NSShadow()
    glintShadow.shadowColor = NSColor.white.withAlphaComponent(0.95)
    glintShadow.shadowBlurRadius = 8
    glintShadow.shadowOffset = .zero
    glintShadow.set()
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillEllipse(in: CGRect(x: center.x - 3.5, y: center.y - 3.5, width: 7, height: 7))
    ctx.restoreGState()

    // MARK: - 8. Top Specular Sheen & Glass Bezel Rim
    let sheenPath = CGMutablePath()
    sheenPath.move(to: CGPoint(x: 100, y: 560))
    sheenPath.addCurve(to: CGPoint(x: 924, y: 560), control1: CGPoint(x: 350, y: 630), control2: CGPoint(x: 674, y: 630))
    sheenPath.addLine(to: CGPoint(x: 924, y: 924))
    sheenPath.addLine(to: CGPoint(x: 100, y: 924))
    sheenPath.closeSubpath()

    ctx.saveGState()
    ctx.addPath(sheenPath)
    ctx.clip()
    let sheenColors = [
        NSColor(white: 1.0, alpha: 0.08).cgColor,
        NSColor(white: 1.0, alpha: 0.0).cgColor
    ] as CFArray
    if let sheenGrad = CGGradient(colorsSpace: colorSpace, colors: sheenColors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(sheenGrad, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 560), options: [])
    }
    ctx.restoreGState()

    // Inner Rim: 2px metallic highlight along squircle edge
    ctx.setLineWidth(2.2)
    ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.28).cgColor)
    ctx.addPath(squirclePath)
    ctx.strokePath()

    ctx.restoreGState() // End squircle clip
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

    // Generate all standard macOS icon resolutions
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
