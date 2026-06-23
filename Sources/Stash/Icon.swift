import AppKit

/// Custom menu-bar icon: a clipboard with a top clip and a few entry lines,
/// matching the app icon. Drawn as a template image so the system tints it
/// correctly for light/dark menu bars and Reduce-Transparency.
enum AppIcon {
    static func menuBar() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.black.set()

            // Board outline (centred on x = 9).
            let board = NSBezierPath(roundedRect: NSRect(x: 4.6, y: 3.2, width: 8.8, height: 11.0),
                                     xRadius: 1.9, yRadius: 1.9)
            board.lineWidth = 1.4
            board.stroke()

            // Clip at the top.
            let clip = NSBezierPath(roundedRect: NSRect(x: 7.25, y: 13.3, width: 3.5, height: 2.0),
                                    xRadius: 0.7, yRadius: 0.7)
            clip.fill()

            // Entry lines inside the board.
            let lines: [(CGFloat, CGFloat, CGFloat)] = [   // (y, xStart, xEnd)
                (11.4, 6.3, 11.1),
                (9.3,  6.3, 9.9),
                (7.2,  6.3, 10.6),
            ]
            for (y, x0, x1) in lines {
                let p = NSBezierPath()
                p.move(to: NSPoint(x: x0, y: y))
                p.line(to: NSPoint(x: x1, y: y))
                p.lineWidth = 1.2
                p.lineCapStyle = .round
                p.stroke()
            }

            return true
        }
        image.isTemplate = true
        return image
    }
}
