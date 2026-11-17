// Draws Direct's app icon (the signpost mark on a dark tile) and writes Support/AppIcon.icns.
// Run from the repo root: swift scripts/make-icon.swift
import AppKit

// The same parts as DirectMark in Sources/Direct/Theme.swift, on a 24-unit grid with y pointing down.
let markParts: [(points: [CGPoint], closed: Bool, width: CGFloat, filled: Bool)] = [
    ([CGPoint(x: 12, y: 11.2), CGPoint(x: 12, y: 12.3)], false, 2.2, false),
    ([CGPoint(x: 12, y: 19.2), CGPoint(x: 12, y: 21.5)], false, 2.2, false),
    ([CGPoint(x: 17, y: 13.4), CGPoint(x: 8.6, y: 13.4), CGPoint(x: 5.6, y: 15.8),
      CGPoint(x: 8.6, y: 18.2), CGPoint(x: 17, y: 18.2)], true, 1.8, false),
    ([CGPoint(x: 7, y: 4.4), CGPoint(x: 15.4, y: 4.4), CGPoint(x: 18.4, y: 6.8),
      CGPoint(x: 15.4, y: 9.2), CGPoint(x: 7, y: 9.2)], true, 2.0, true),
]

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

    // The mark, on a 24-unit grid, filling 62% of the tile.
    let markSize = tile.width * 0.62
    let unit = markSize / 24
    let origin = NSPoint(x: tile.midX - markSize / 2, y: tile.midY + markSize / 2)
    func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: origin.x + x * unit, y: origin.y - y * unit) }
    // Thin strokes vanish at 16 and 32 px.
    let weight: CGFloat = pixels <= 32 ? 1.25 : 1
    NSColor(srgbRed: 0.894, green: 0.851, blue: 1, alpha: 1).set()
    for part in markParts {
        let path = NSBezierPath()
        path.move(to: p(part.points[0].x, part.points[0].y))
        part.points.dropFirst().forEach { path.line(to: p($0.x, $0.y)) }
        if part.closed { path.close() }
        path.lineWidth = part.width * unit * weight
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        if part.filled { path.fill() }
        path.stroke()
    }
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
