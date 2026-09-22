import AppKit

let output = CommandLine.arguments[1] + "/AppIcon.iconset"
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
  for scale in [1, 2] {
    let pixels = size * scale
    let image = NSImage(size: NSSize(width: 1024, height: 1024))
    image.lockFocus()
    NSColor(srgbRed: 0.91, green: 0.93, blue: 0.95, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 45, y: 45, width: 934, height: 934), xRadius: 200, yRadius: 200).fill()
    let shadow = NSShadow()
    shadow.shadowColor = .black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = 30
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    let body = NSBezierPath()
    body.move(to: NSPoint(x: 365, y: 630))
    body.curve(to: NSPoint(x: 365, y: 350), controlPoint1: NSPoint(x: 420, y: 510), controlPoint2: NSPoint(x: 330, y: 460))
    body.curve(to: NSPoint(x: 660, y: 350), controlPoint1: NSPoint(x: 370, y: 180), controlPoint2: NSPoint(x: 655, y: 180))
    body.curve(to: NSPoint(x: 660, y: 630), controlPoint1: NSPoint(x: 695, y: 460), controlPoint2: NSPoint(x: 605, y: 510))
    body.curve(to: NSPoint(x: 365, y: 630), controlPoint1: NSPoint(x: 780, y: 875), controlPoint2: NSPoint(x: 245, y: 875))
    body.close()
    NSColor(srgbRed: 0.12, green: 0.13, blue: 0.15, alpha: 1).setFill()
    body.fill()
    let hand = NSBezierPath()
    hand.move(to: NSPoint(x: 512, y: 758))
    hand.line(to: NSPoint(x: 512, y: 650))
    hand.line(to: NSPoint(x: 582, y: 650))
    hand.lineWidth = 44
    hand.lineCapStyle = .round
    hand.lineJoinStyle = .round
    NSColor(srgbRed: 0.72, green: 0.37, blue: 0.87, alpha: 1).setStroke()
    hand.stroke()
    image.unlockFocus()
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    let suffix = scale == 2 ? "@2x" : ""
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output + "/icon_\(size)x\(size)\(suffix).png"))
  }
}
