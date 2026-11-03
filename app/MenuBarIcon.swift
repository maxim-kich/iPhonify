import AppKit

enum MenuBarIcon {
 static func make() -> NSImage {
  // Two Fields: the selected 20-unit vector, drawn at 18 points for the menu bar.
  let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
   NSColor.black.setStroke()
   NSColor.black.setFill()
   for center in [NSPoint(x: 6.3, y: 6.3), NSPoint(x: 11.7, y: 11.7)] {
    let ring = NSBezierPath(ovalIn: NSRect(x: center.x - 4.5, y: center.y - 4.5, width: 9, height: 9))
    ring.lineWidth = 1.26
    ring.stroke()
    NSBezierPath(ovalIn: NSRect(x: center.x - 1.35, y: center.y - 1.35, width: 2.7, height: 2.7)).fill()
   }
   return true
  }
  image.isTemplate = true
  image.accessibilityDescription = "iPhonify"
  return image
 }
}
