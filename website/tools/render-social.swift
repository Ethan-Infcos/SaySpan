import AppKit

let output = CommandLine.arguments[1]
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1200, pixelsHigh: 630,
                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                             isPlanar: false, colorSpaceName: .deviceRGB,
                             bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
func color(_ hex: UInt32) -> NSColor {
    NSColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: 1)
}
func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ hex: UInt32, _ radius: CGFloat = 0) {
    color(hex).setFill()
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: radius, yRadius: radius).fill()
}
func text(_ value: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ hex: UInt32, _ weight: NSFont.Weight = .regular) {
    (value as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color(hex)])
}
rect(0, 0, 1200, 630, 0xf7f8f5)
rect(60, 504, 52, 52, 0x162d2e, 15)
text("S", 72, 510, 37, 0xd8ff8a, .bold)
text("SaySpan", 126, 509, 36, 0x162d2e, .semibold)
text("Your words.", 60, 338, 76, 0x162d2e, .semibold)
rect(58, 257, 552, 16, 0xd8ff8a, 3)
text("Across languages.", 60, 255, 67, 0x162d2e, .semibold)
text("Think in your language. Say it in another.", 64, 181, 25, 0x5d6e6b)
text("sayspan.com", 64, 66, 21, 0x5d6e6b, .medium)
rect(713, 117, 427, 350, 0xe8e6f8, 40)
rect(746, 168, 355, 245, 0xffffff, 18)
text("S  SaySpan", 769, 367, 18, 0x162d2e, .semibold)
text("你好，世界。", 771, 305, 31, 0x162d2e)
rect(769, 289, 306, 1, 0xdce3dc)
text("Hello, world.", 771, 232, 32, 0x162d2e, .medium)
text("Enter: original     Tab: translation", 770, 192, 14, 0x5d6e6b)
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
