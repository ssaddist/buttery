import AppKit

let width: CGFloat = 660
let height: CGFloat = 400
let scale = CommandLine.arguments.count > 2 ? CGFloat(Double(CommandLine.arguments[2]) ?? 1) : 1
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "background.png"

func color(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: width, height: height)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let full = NSRect(x: 0, y: 0, width: width, height: height)
NSGradient(colors: [color(0xFFF8E8), color(0xFCE9BC)])!.draw(in: full, angle: -90)
NSGradient(colors: [color(0xFFD66B, 0.35), color(0xFFD66B, 0)])!
    .draw(fromCenter: NSPoint(x: width / 2, y: 210), radius: 0, toCenter: NSPoint(x: width / 2, y: 210), radius: 300, options: [])

func top(_ y: CGFloat) -> CGFloat { height - y }

func text(_ s: String, size: CGFloat, weight: NSFont.Weight, color c: NSColor, centerY: CGFloat, rounded: Bool = false) {
    var font = NSFont.systemFont(ofSize: size, weight: weight)
    if rounded, let d = font.fontDescriptor.withDesign(.rounded), let f = NSFont(descriptor: d, size: size) { font = f }
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: c]
    let str = NSAttributedString(string: s, attributes: attrs)
    let sz = str.size()
    str.draw(at: NSPoint(x: (width - sz.width) / 2, y: top(centerY) - sz.height / 2))
}

text("Buttery", size: 30, weight: .heavy, color: color(0x3A2A14), centerY: 52, rounded: true)
text("Drag Buttery to Applications  ·  Перетащите Buttery в «Программы»", size: 13, weight: .medium,
     color: color(0x3A2A14, 0.6), centerY: 86)

let y = top(190)
let arrow = NSBezierPath()
arrow.lineWidth = 5
arrow.lineCapStyle = .round
arrow.setLineDash([0.1, 12], count: 2, phase: 0)
arrow.move(to: NSPoint(x: 262, y: y))
arrow.line(to: NSPoint(x: 386, y: y))
color(0xF4A63A).setStroke()
arrow.stroke()

let head = NSBezierPath()
head.lineWidth = 5
head.lineCapStyle = .round
head.lineJoinStyle = .round
head.move(to: NSPoint(x: 384, y: y + 15))
head.line(to: NSPoint(x: 400, y: y))
head.line(to: NSPoint(x: 384, y: y - 15))
head.stroke()

text("First launch: right-click the app → Open  ·  Первый запуск: правый клик → Открыть", size: 11, weight: .regular,
     color: color(0x3A2A14, 0.45), centerY: 360)

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
