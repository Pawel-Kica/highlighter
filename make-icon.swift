// Renders AppIcon.icns: a white pen on the #2B2B2A dock tile, up to 1024 px (the icns max).
// Run here: swift make-icon.swift (build.sh copies AppIcon.icns into the app)
import AppKit

let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    // macOS icon grid: the tile is ~80% of the canvas.
    let tile = NSRect(x: 0, y: 0, width: s, height: s).insetBy(dx: s * 0.1, dy: s * 0.1)
    NSColor(srgbRed: 0x2B / 255, green: 0x2B / 255, blue: 0x2A / 255, alpha: 1).setFill()
    NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225).fill()

    let config = NSImage.SymbolConfiguration(pointSize: s * 0.5, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor(srgbRed: 0xF9 / 255, green: 0xFD / 255, blue: 1, alpha: 1)]))
    let glyph = NSImage(systemSymbolName: "pencil", accessibilityDescription: nil)!.withSymbolConfiguration(config)!
    glyph.draw(in: NSRect(x: (s - glyph.size.width) / 2, y: (s - glyph.size.height) / 2, width: glyph.size.width, height: glyph.size.height))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    try render(points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try render(points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
try render(1024).write(to: URL(fileURLWithPath: "/tmp/highlighter-icon-preview.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", "AppIcon.icns"]
try iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "Wrote AppIcon.icns" : "iconutil failed")
