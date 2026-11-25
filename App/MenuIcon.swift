import AppKit

enum MenuIcon {
    enum Badge { case none, charging, discharging }

    private static var cache: [String: NSImage] = [:]

    static func image(badge: Badge) -> NSImage {
        let key = "\(badge)"
        if let img = cache[key] { return img }
        let size = NSSize(width: 22, height: 16)
        let img = NSImage(size: size, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            NSColor.black.setFill()
            NSColor.black.setStroke()

            NSBezierPath(ovalIn: NSRect(x: 0.5, y: 1.0, width: 21, height: 7)).fill()
            ctx.setBlendMode(.clear)
            NSBezierPath(ovalIn: NSRect(x: 2.3, y: 2.4, width: 17.4, height: 4.4)).fill()
            ctx.setBlendMode(.normal)

            let front = NSRect(x: 4.2, y: 4.4, width: 11, height: 4.6)
            let block = NSBezierPath()
            block.move(to: NSPoint(x: front.minX, y: front.minY))
            block.line(to: NSPoint(x: front.maxX, y: front.minY))
            block.line(to: NSPoint(x: front.maxX + 2.6, y: front.minY + 2.4))
            block.line(to: NSPoint(x: front.maxX + 2.6, y: front.maxY + 2.4))
            block.line(to: NSPoint(x: front.minX + 2.6, y: front.maxY + 2.4))
            block.line(to: NSPoint(x: front.minX, y: front.maxY))
            block.close()
            block.lineJoinStyle = .round

            ctx.setBlendMode(.clear)
            block.lineWidth = 2.2
            block.stroke()
            ctx.setBlendMode(.normal)
            block.fill()
            block.lineWidth = 0.8
            block.stroke()

            ctx.setBlendMode(.clear)
            let edges = NSBezierPath()
            edges.move(to: NSPoint(x: front.minX + 0.9, y: front.maxY))
            edges.line(to: NSPoint(x: front.maxX, y: front.maxY))
            edges.line(to: NSPoint(x: front.maxX + 1.9, y: front.maxY + 1.75))
            edges.move(to: NSPoint(x: front.maxX, y: front.maxY))
            edges.line(to: NSPoint(x: front.maxX, y: front.minY + 0.8))
            edges.lineWidth = 0.7
            edges.stroke()

            switch badge {
            case .charging:
                let c = NSPoint(x: front.midX, y: front.midY)
                let bolt = NSBezierPath()
                bolt.move(to: NSPoint(x: c.x + 0.9, y: c.y + 2.5))
                bolt.line(to: NSPoint(x: c.x - 1.6, y: c.y - 0.2))
                bolt.line(to: NSPoint(x: c.x + 0.1, y: c.y - 0.2))
                bolt.line(to: NSPoint(x: c.x - 0.9, y: c.y - 2.5))
                bolt.line(to: NSPoint(x: c.x + 1.6, y: c.y + 0.4))
                bolt.line(to: NSPoint(x: c.x - 0.1, y: c.y + 0.4))
                bolt.close()
                bolt.fill()
            case .discharging:
                NSBezierPath(roundedRect: NSRect(x: front.midX - 2.2, y: front.midY - 0.55, width: 4.4, height: 1.1),
                             xRadius: 0.55, yRadius: 0.55).fill()
            case .none:
                break
            }
            ctx.setBlendMode(.normal)
            return true
        }
        img.isTemplate = true
        cache[key] = img
        return img
    }
}
