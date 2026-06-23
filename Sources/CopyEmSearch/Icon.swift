import AppKit

/// Custom menu-bar icon: a magnifier lens containing a small stack of clipboard
/// "entries" (lines), with a bold rounded handle. Drawn as a template image so the
/// system tints it correctly for light/dark menu bars and Reduce-Transparency.
enum AppIcon {
    static func menuBar() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.black.set()

            // Lens
            let center = NSPoint(x: 7.6, y: 10.4)
            let radius: CGFloat = 5.0
            let lensRect = NSRect(x: center.x - radius, y: center.y - radius,
                                  width: radius * 2, height: radius * 2)
            let lens = NSBezierPath(ovalIn: lensRect)
            lens.lineWidth = 1.8
            lens.stroke()

            // Clipboard "entries" — three short lines inside the lens.
            let lines: [(CGFloat, CGFloat, CGFloat)] = [   // (y, xStart, xEnd)
                (11.7, 4.9, 10.4),
                (10.2, 4.9, 9.6),
                (8.7,  4.9, 10.1),
            ]
            for (y, x0, x1) in lines {
                let p = NSBezierPath()
                p.move(to: NSPoint(x: x0, y: y))
                p.line(to: NSPoint(x: x1, y: y))
                p.lineWidth = 1.2
                p.lineCapStyle = .round
                p.stroke()
            }

            // Handle
            let handle = NSBezierPath()
            handle.move(to: NSPoint(x: 11.15, y: 6.85))
            handle.line(to: NSPoint(x: 15.6, y: 2.4))
            handle.lineWidth = 2.2
            handle.lineCapStyle = .round
            handle.stroke()

            return true
        }
        image.isTemplate = true
        return image
    }
}
