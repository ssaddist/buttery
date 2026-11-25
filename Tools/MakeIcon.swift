import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

func color(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

let inset: CGFloat = 100
let bgRect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let bg = NSBezierPath(roundedRect: bgRect, xRadius: 185, yRadius: 185)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: NSColor.black.withAlphaComponent(0.35).cgColor)
color(0x2A2016).setFill(); bg.fill()
ctx.restoreGState()
NSGradient(colors: [color(0x3B2D1B), color(0x18120B)])!.draw(in: bg, angle: -90)

NSGradient(colors: [color(0xFFC94A, 0.28), color(0xFFC94A, 0)])!
    .draw(fromCenter: NSPoint(x: 512, y: 540), radius: 0, toCenter: NSPoint(x: 512, y: 540), radius: 380, options: [])

let body = NSRect(x: 222, y: 400, width: 540, height: 300)
let butterPath = NSBezierPath(roundedRect: body, xRadius: 62, yRadius: 62)

let drips: [(x: CGFloat, w: CGFloat, len: CGFloat)] = [(300, 70, 120), (420, 54, 70), (590, 80, 165), (690, 46, 60)]
for d in drips {
    let r = d.w / 2
    let p = NSBezierPath()
    p.move(to: NSPoint(x: d.x - r - 18, y: body.minY + 40))
    p.curve(to: NSPoint(x: d.x - r, y: body.minY - 10), controlPoint1: NSPoint(x: d.x - r - 4, y: body.minY + 30),
            controlPoint2: NSPoint(x: d.x - r, y: body.minY + 10))
    p.line(to: NSPoint(x: d.x - r, y: body.minY - d.len))
    p.appendArc(withCenter: NSPoint(x: d.x, y: body.minY - d.len), radius: r, startAngle: 180, endAngle: 360)
    p.line(to: NSPoint(x: d.x + r, y: body.minY - 10))
    p.curve(to: NSPoint(x: d.x + r + 18, y: body.minY + 40), controlPoint1: NSPoint(x: d.x + r, y: body.minY + 10),
            controlPoint2: NSPoint(x: d.x + r + 4, y: body.minY + 30))
    p.close()
    butterPath.append(p)
}

let nub = NSBezierPath(roundedRect: NSRect(x: body.maxX + 16, y: body.midY - 62, width: 42, height: 124), xRadius: 18, yRadius: 18)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 26, color: NSColor.black.withAlphaComponent(0.45).cgColor)
color(0xFFD25A).setFill(); butterPath.fill(); nub.fill()
ctx.restoreGState()
NSGradient(colors: [color(0xFFEB9C), color(0xFFD35C), color(0xF2AE36)])!.draw(in: butterPath, angle: -90)
NSGradient(colors: [color(0xFFE48A), color(0xF0B040)])!.draw(in: nub, angle: -90)

let shine = NSBezierPath(roundedRect: NSRect(x: body.minX + 40, y: body.maxY - 70, width: body.width - 80, height: 34),
                         xRadius: 17, yRadius: 17)
color(0xFFFFFF, 0.38).setFill(); shine.fill()

let bolt = NSBezierPath()
let cx = body.midX - 8, cy = body.midY - 6
bolt.move(to: NSPoint(x: cx + 34, y: cy + 112))
bolt.line(to: NSPoint(x: cx - 58, y: cy - 8))
bolt.line(to: NSPoint(x: cx + 4, y: cy - 8))
bolt.line(to: NSPoint(x: cx - 26, y: cy - 112))
bolt.line(to: NSPoint(x: cx + 66, y: cy + 18))
bolt.line(to: NSPoint(x: cx + 4, y: cy + 18))
bolt.close()
bolt.lineJoinStyle = .round
color(0xB06A12, 0.55).setFill(); bolt.fill()
color(0xFFF3C4, 0.5).setStroke(); bolt.lineWidth = 4
ctx.saveGState(); ctx.translateBy(x: 2, y: -3); bolt.stroke(); ctx.restoreGState()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("icon → \(out)")
