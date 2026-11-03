import AppKit

// Package full-bleed artwork in a clean macOS icon silhouette with transparent margins.
let source = CommandLine.arguments[1]
let destination = CommandLine.arguments[2]
guard let artwork = NSImage(contentsOfFile: source),
 let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
 let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
 fatalError("Unable to prepare app icon")
}
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.imageInterpolation = .high
context.shouldAntialias = true
let bounds = NSRect(x: 100, y: 100, width: 824, height: 824)
NSBezierPath(roundedRect: bounds, xRadius: 185, yRadius: 185).addClip()
artwork.draw(in: bounds, from: .zero, operation: .copy, fraction: 1)
context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()
guard let png = bitmap.representation(using: .png, properties: [:]) else {
 fatalError("Unable to encode app icon")
}
try png.write(to: URL(fileURLWithPath: destination))
