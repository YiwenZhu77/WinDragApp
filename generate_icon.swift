#!/usr/bin/swift

import Cocoa

// Generate app icon with "Win" and "Drag" text inside the box
func generateAppIcon(size: Int, outputPath: String) {
    // Create bitmap representation at exact pixel size (1x scale)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    
    let s = CGFloat(size)
    let padding = s * 0.06
    let rect = NSRect(x: padding, y: padding, width: s - padding * 2, height: s - padding * 2)
    let cornerRadius = s * 0.15
    
    // Gradient background
    let bgPath = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
    let gradient = NSGradient(colorsAndLocations: 
        (NSColor(red: 0.35, green: 0.55, blue: 0.95, alpha: 1.0), 0.0),
        (NSColor(red: 0.55, green: 0.35, blue: 0.85, alpha: 1.0), 1.0)
    )!
    gradient.draw(in: bgPath, angle: -45)
    
    // Add subtle shadow to text
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.015)
    shadow.shadowBlurRadius = s * 0.02
    
    // Draw "Win" text inside the box (upper)
    let fontSize = s * 0.32
    let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
    let text = "Win"
    let textAttrsWithShadow: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white,
        .shadow: shadow
    ]
    let textSize = text.size(withAttributes: textAttrsWithShadow)
    let textX = (s - textSize.width) / 2
    let textY = s * 0.52
    text.draw(at: NSPoint(x: textX, y: textY), withAttributes: textAttrsWithShadow)
    
    // "Drag" text inside the box (lower)
    let tapFontSize = s * 0.32
    let tapFont = NSFont.systemFont(ofSize: tapFontSize, weight: .bold)
    let tapText = "Drag"
    let tapAttrs: [NSAttributedString.Key: Any] = [
        .font: tapFont,
        .foregroundColor: NSColor.white,
        .shadow: shadow
    ]
    let tapSize = tapText.size(withAttributes: tapAttrs)
    let tapX = (s - tapSize.width) / 2
    let tapY = s * 0.22
    tapText.draw(at: NSPoint(x: tapX, y: tapY), withAttributes: tapAttrs)
    
    NSGraphicsContext.restoreGraphicsState()
    
    if let pngData = rep.representation(using: .png, properties: [:]) {
        try? pngData.write(to: URL(fileURLWithPath: outputPath))
        print("Generated: \(outputPath)")
    }
}

// Generate menu bar icon
func generateMenuBarIcon(size: Int, outputPath: String) {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    
    let s = CGFloat(size)
    
    // Draw "WD" in black (template mode)
    let fontSize = s * 0.45
    let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
    
    let text = "WD"
    let textAttrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.black
    ]
    
    let textSize = text.size(withAttributes: textAttrs)
    let textX = (s - textSize.width) / 2
    let textY = (s - textSize.height) / 2
    
    text.draw(at: NSPoint(x: textX, y: textY), withAttributes: textAttrs)
    
    NSGraphicsContext.restoreGraphicsState()
    
    if let pngData = rep.representation(using: .png, properties: [:]) {
        try? pngData.write(to: URL(fileURLWithPath: outputPath))
        print("Generated: \(outputPath)")
    }
}

// Generate all sizes (only those referenced in Contents.json)
let basePath = "WinDragApp/Assets.xcassets/AppIcon.appiconset"

for size in [16, 32, 128, 256, 512] {
    generateAppIcon(size: size, outputPath: "\(basePath)/icon_\(size)x\(size).png")
}

for size in [16, 32, 128, 256, 512] {
    generateAppIcon(size: size * 2, outputPath: "\(basePath)/icon_\(size)x\(size)@2x.png")
}

generateMenuBarIcon(size: 18, outputPath: "WinDragApp/Assets.xcassets/MenuBarIcon.imageset/menubar_18.png")
generateMenuBarIcon(size: 36, outputPath: "WinDragApp/Assets.xcassets/MenuBarIcon.imageset/menubar_36.png")

print("\n✅ All icons generated!")
