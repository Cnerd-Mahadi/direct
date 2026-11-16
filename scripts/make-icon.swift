// Draws Direct's app icon (the fork mark on a dark tile) and writes Support/AppIcon.icns.
// Run from the repo root: swift scripts/make-icon.swift
import AppKit

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

    // The mark, on a 24-unit grid, filling 56% of the tile.
    let markSize = tile.width * 0.56
    let unit = markSize / 24
    let origin = NSPoint(x: tile.midX - markSize / 2, y: tile.midY + markSize / 2)
    func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: origin.x + x * unit, y: origin.y - y * unit) }
    let mark = NSBezierPath()
    for segment in [[p(12, 21), p(12, 13), p(6, 7)], [p(12, 13), p(18, 7)], [p(5, 11), p(5, 6), p(10, 6)],
                    [p(19, 11), p(19, 6), p(14, 6)]] {
        mark.move(to: segment[0])
        segment.dropFirst().forEach(mark.line)
    }
    mark.lineWidth = unit * (pixels <= 32 ? 2.8 : 2.2)
    mark.lineCapStyle = .round
    mark.lineJoinStyle = .round
    NSColor(srgbRed: 0.894, green: 0.851, blue: 1, alpha: 1).setStroke()
    mark.stroke()
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
