// Menu bar glyph: a solid owl silhouette. Eyes closed = normal sleep, eyes open and green = staying awake.

import AppKit

enum OwlIcon {
    static let awakeColor = NSColor.systemGreen

    static func image(awake: Bool) -> NSImage {
        // Solid silhouette with the eyes cut out: at menu bar size thin lines turn to mush,
        // big shapes stay readable.
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size, flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current else { return false }
            (awake ? awakeColor : NSColor.black).setFill()

            // Ear tufts, the V dip between them, egg-shaped body.
            let body = NSBezierPath()
            body.move(to: NSPoint(x: 2.2, y: 0.6))
            body.line(to: NSPoint(x: 6.2, y: 3.4))
            body.curve(to: NSPoint(x: 9, y: 4.6),
                       controlPoint1: NSPoint(x: 7.3, y: 3.6), controlPoint2: NSPoint(x: 8.3, y: 3.9))
            body.curve(to: NSPoint(x: 11.8, y: 3.4),
                       controlPoint1: NSPoint(x: 9.7, y: 3.9), controlPoint2: NSPoint(x: 10.7, y: 3.6))
            body.line(to: NSPoint(x: 15.8, y: 0.6))
            body.curve(to: NSPoint(x: 9, y: 17.6),
                       controlPoint1: NSPoint(x: 18.6, y: 7.0), controlPoint2: NSPoint(x: 16.6, y: 17.6))
            body.curve(to: NSPoint(x: 2.2, y: 0.6),
                       controlPoint1: NSPoint(x: 1.4, y: 17.6), controlPoint2: NSPoint(x: -0.6, y: 7.0))
            body.close()
            body.fill()

            let eyes = [NSPoint(x: 5.6, y: 8.6), NSPoint(x: 12.4, y: 8.6)]
            ctx.compositingOperation = .clear
            for c in eyes {
                if awake {
                    // Big round eye holes.
                    NSBezierPath(ovalIn: NSRect(x: c.x - 3.0, y: c.y - 3.0, width: 6.0, height: 6.0)).fill()
                } else {
                    // Closed eyes: thick lids carved into the silhouette.
                    let lid = NSBezierPath()
                    lid.move(to: NSPoint(x: c.x - 2.0, y: c.y - 0.2))
                    lid.curve(to: NSPoint(x: c.x + 2.0, y: c.y - 0.2),
                              controlPoint1: NSPoint(x: c.x - 1.0, y: c.y + 1.6),
                              controlPoint2: NSPoint(x: c.x + 1.0, y: c.y + 1.6))
                    lid.lineWidth = 1.7
                    lid.lineCapStyle = .round
                    lid.stroke()
                }
            }
            // Beak notch.
            let beak = NSBezierPath()
            beak.move(to: NSPoint(x: 7.7, y: 12.2))
            beak.line(to: NSPoint(x: 10.3, y: 12.2))
            beak.line(to: NSPoint(x: 9, y: 14.6))
            beak.close()
            beak.fill()

            ctx.compositingOperation = .sourceOver
            if awake {
                // Pupils inside the holes.
                for c in eyes {
                    NSBezierPath(ovalIn: NSRect(x: c.x - 1.5, y: c.y - 1.5, width: 3.0, height: 3.0)).fill()
                }
            }
            return true
        }
        // Asleep the glyph follows the menu bar's light/dark look; awake it keeps its green.
        img.isTemplate = !awake
        img.accessibilityDescription = awake ? L("Не засыпает", "Staying awake") : L("Обычный сон", "Normal sleep")
        return img
    }
}
