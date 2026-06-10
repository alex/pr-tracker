// Renders the app icon (blue squircle + white branch glyph) into an .iconset
// directory, headlessly — no Xcode, no asset catalog.
//
//   swift Tools/make-icon.swift /path/to/AppIcon.iconset
//
// Then: iconutil -c icns /path/to/AppIcon.iconset -o AppIcon.icns

import AppKit

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <output.iconset>\n".utf8))
    exit(1)
}
let outDir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func bitmap(_ px: Int) -> NSBitmapImageRep {
    NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
}

// ---- master render at 1024 ----
let master = bitmap(1024)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: master)

// Big Sur-style icon grid: 824×824 squircle centered on a 1024 canvas.
let squircle = NSBezierPath(
    roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824),
    xRadius: 185, yRadius: 185
)

// soft drop shadow under the plate
NSGraphicsContext.current?.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowOffset = NSSize(width: 0, height: -14)
shadow.shadowBlurRadius = 28
shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
shadow.set()
NSColor.white.setFill()
squircle.fill()
NSGraphicsContext.current?.restoreGraphicsState()

// blue gradient, lighter at the top
NSGradient(
    starting: NSColor(calibratedRed: 0.32, green: 0.64, blue: 1.0, alpha: 1),
    ending: NSColor(calibratedRed: 0.0, green: 0.42, blue: 0.92, alpha: 1)
)!.draw(in: squircle, angle: -90)

// subtle top inner highlight
NSGraphicsContext.current?.saveGraphicsState()
squircle.addClip()
NSColor.white.withAlphaComponent(0.25).setStroke()
let highlight = NSBezierPath(
    roundedRect: NSRect(x: 103, y: 103, width: 818, height: 818),
    xRadius: 182, yRadius: 182
)
highlight.lineWidth = 6
highlight.stroke()
NSGraphicsContext.current?.restoreGraphicsState()

// white branch glyph (same symbol as the app's empty state)
let config = NSImage.SymbolConfiguration(pointSize: 520, weight: .medium)
    .applying(.init(paletteColors: [.white]))
if let symbol = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: nil)?
    .withSymbolConfiguration(config) {
    let s = symbol.size
    let maxDim: CGFloat = 470
    let scale = maxDim / max(s.width, s.height)
    let w = s.width * scale, h = s.height * scale
    symbol.draw(
        in: NSRect(x: (1024 - w) / 2, y: (1024 - h) / 2, width: w, height: h),
        from: .zero, operation: .sourceOver, fraction: 1
    )
}

NSGraphicsContext.restoreGraphicsState()

// ---- downscale to all iconset sizes ----
let full = NSImage(size: NSSize(width: 1024, height: 1024))
full.addRepresentation(master)

func write(px: Int, name: String) {
    let rep = bitmap(px)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    full.draw(
        in: NSRect(x: 0, y: 0, width: px, height: px),
        from: .zero, operation: .copy, fraction: 1
    )
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!
        .write(to: outDir.appendingPathComponent(name))
}

write(px: 16, name: "icon_16x16.png")
write(px: 32, name: "icon_16x16@2x.png")
write(px: 32, name: "icon_32x32.png")
write(px: 64, name: "icon_32x32@2x.png")
write(px: 128, name: "icon_128x128.png")
write(px: 256, name: "icon_128x128@2x.png")
write(px: 256, name: "icon_256x256.png")
write(px: 512, name: "icon_256x256@2x.png")
write(px: 512, name: "icon_512x512.png")
write(px: 1024, name: "icon_512x512@2x.png")
print("iconset written to \(outDir.path)")
