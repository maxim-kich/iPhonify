import AppKit

// Keep the app and Applications folder as real draggable Finder icons.
let size = NSSize(width: 600, height: 360)
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1200, pixelsHigh: 720,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
bitmap.size = size
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor(calibratedRed: 0.98, green: 0.95, blue: 0.98, alpha: 1).setFill()
NSRect(origin: .zero, size: size).fill()
let artwork = NSImage(contentsOfFile: "assets/app-icon.png")!
// Rotate and scale the original touch-field centers onto Finder's icon centers.
// Source coordinates use AppKit's bottom-left image origin.
let peachCenter = NSPoint(x: 370, y: 624)
let lavenderCenter = NSPoint(x: 646, y: 378)
let dx = lavenderCenter.x - peachCenter.x
let dy = lavenderCenter.y - peachCenter.y
let transform = NSAffineTransform()
transform.translateX(by: 138, yBy: 180)
transform.rotate(byRadians: -atan2(dy, dx))
// Overscan the rotated artwork so its rounded outer edges stay outside the window.
let scale = 324 / hypot(dx, dy)
transform.scale(by: scale)
transform.translateX(by: -peachCenter.x, yBy: -peachCenter.y)
NSGraphicsContext.saveGraphicsState()
transform.concat()
artwork.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024))
NSGraphicsContext.restoreGraphicsState()
NSColor.white.withAlphaComponent(0.70).setFill()
NSRect(origin: .zero, size: size).fill()
func label(_ text: String, y: CGFloat, font: NSFont, color: NSColor) {
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let width = (text as NSString).size(withAttributes: attributes).width
    (text as NSString).draw(at: NSPoint(x: (size.width - width) / 2, y: y), withAttributes: attributes)
}
let ink = NSColor(calibratedRed: 0.25, green: 0.23, blue: 0.37, alpha: 1)
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 278, y: 180)); arrow.line(to: NSPoint(x: 322, y: 180))
arrow.move(to: NSPoint(x: 313, y: 189)); arrow.line(to: NSPoint(x: 322, y: 180))
arrow.line(to: NSPoint(x: 313, y: 171))
arrow.lineWidth = 2; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
ink.withAlphaComponent(0.55).setStroke(); arrow.stroke()
label("Drag iPhonify to Applications", y: 42,
      font: .systemFont(ofSize: 13, weight: .medium), color: ink.withAlphaComponent(0.8))
NSGraphicsContext.restoreGraphicsState()
try bitmap.tiffRepresentation!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
