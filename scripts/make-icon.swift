// Draws Direct's app icon (the solid disc mark on a dark tile) and writes Support/AppIcon.icns.
// Run from the repo root: swift scripts/make-icon.swift
import AppKit

let mark = NSImage(contentsOf: URL(filePath: "Support/Mark.svg"))!
let lavender = NSColor(srgbRed: 0.894, green: 0.851, blue: 1, alpha: 1)

func render(_ pixels: Int) -> Data {
    let size = CGFloat(pixels)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    // macOS icon grid: an 824/1024 tile, centered, with a soft drop shadow.
    let inset = size * 100 / 1024
    let tile = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let shape = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowOffset = NSSize(width: 0, height: -size * 0.012)
    shadow.shadowBlurRadius = size * 0.03
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor(srgbRed: 0.07, green: 0.07, blue: 0.07, alpha: 1).setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: NSColor(srgbRed: 0.165, green: 0.165, blue: 0.165, alpha: 1),
               ending: NSColor(srgbRed: 0.07, green: 0.07, blue: 0.07, alpha: 1))!.draw(in: shape, angle: -90)
    NSColor.white.withAlphaComponent(0.06).setStroke()
    shape.lineWidth = max(1, size / 512)
    shape.stroke()

    // The disc spans 216 of the mark's 256 units, so a 68% mark gives a disc about 57% of the tile.
    // Small sizes get a bigger mark, or its strokes vanish.
    let markSize = tile.width * (pixels <= 32 ? 0.84 : 0.68)
    let markRect = NSRect(x: tile.midX - markSize / 2, y: tile.midY - markSize / 2, width: markSize, height: markSize)
    let tinted = NSImage(size: markRect.size, flipped: false) { rect in
        mark.draw(in: rect)
        lavender.set()
        rect.fill(using: .sourceIn)
        return true
    }
    let glow = NSShadow()
    glow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    glow.shadowOffset = NSSize(width: 0, height: -size * 0.006)
    glow.shadowBlurRadius = size * 0.012
    glow.set()
    tinted.draw(in: markRect)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let iconset = URL(filePath: NSTemporaryDirectory()).appending(path: "Direct.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try render(points).write(to: iconset.appending(path: "icon_\(points)x\(points).png"))
    try render(points * 2).write(to: iconset.appending(path: "icon_\(points)x\(points)@2x.png"))
}
let task = Process()
task.executableURL = URL(filePath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", "Support/AppIcon.icns"]
try task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "Wrote Support/AppIcon.icns" : "iconutil failed")
