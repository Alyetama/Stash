import AppKit

/// Custom menu-bar icon: a clipboard with a top clip and a few entry lines,
/// matching the app icon. Drawn as a template image so the system tints it
/// correctly for light/dark menu bars and Reduce-Transparency.
enum AppIcon {
    static func menuBar() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.black.set()

            // Board outline (centred on x = 9), sized to fill the icon like a
            // standard menu-bar glyph.
            let board = NSBezierPath(roundedRect: NSRect(x: 3.6, y: 1.8, width: 10.8, height: 13.0),
                                     xRadius: 2.3, yRadius: 2.3)
            board.lineWidth = 1.5
            board.stroke()

            // Clip at the top.
            let clip = NSBezierPath(roundedRect: NSRect(x: 6.9, y: 13.9, width: 4.2, height: 2.4),
                                    xRadius: 0.9, yRadius: 0.9)
            clip.fill()

            // Entry lines inside the board.
            let lines: [(CGFloat, CGFloat, CGFloat)] = [   // (y, xStart, xEnd)
                (11.4, 5.7, 12.3),
                (8.9,  5.7, 10.7),
                (6.4,  5.7, 11.7),
            ]
            for (y, x0, x1) in lines {
                let p = NSBezierPath()
                p.move(to: NSPoint(x: x0, y: y))
                p.line(to: NSPoint(x: x1, y: y))
                p.lineWidth = 1.4
                p.lineCapStyle = .round
                p.stroke()
            }

            return true
        }
        image.isTemplate = true
        return image
    }
}
