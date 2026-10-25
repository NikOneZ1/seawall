import AppKit

/// The app icon's tilted lock, small enough for the menu bar: an outline at rest, filled with
/// the keyhole cut out while a block runs. Template images, so macOS tints them for the bar.
enum SlabGlyph {
    static let open = draw(locked: false)
    static let locked = draw(locked: true)

    /// How finely the menu bar ring moves: often enough to see, rarely enough to stay cheap.
    static let ringSteps = 48
    private static var rings: [Int: NSImage] = [:]

    /// While blocked: the filled lock inside a ring that fills as the time passes, clockwise from the top.
    @MainActor
    static func ring(step: Int) -> NSImage {
        let step = min(max(step, 0), ringSteps)
        if let image = rings[step] { return image }
        let fraction = CGFloat(step) / CGFloat(ringSteps)
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.set()
            let center = NSPoint(x: 9, y: 9)
            let track = NSBezierPath(ovalIn: NSRect(x: 1.25, y: 1.25, width: 15.5, height: 15.5))
            track.lineWidth = 1.2
            NSGraphicsContext.current?.saveGraphicsState()
            NSColor.black.withAlphaComponent(0.35).set()
            track.stroke()
            NSGraphicsContext.current?.restoreGraphicsState()
            if fraction > 0 {
                let arc = NSBezierPath()
                arc.appendArc(withCenter: center, radius: 7.75, startAngle: -90, endAngle: -90 + 360 * fraction, clockwise: false)
                arc.lineWidth = 2
                arc.lineCapStyle = .round
                arc.stroke()
            }
            // A small solid lock in the middle, tilted like the app's.
            let tilt = NSAffineTransform()
            tilt.translateX(by: 9, yBy: 10)
            tilt.rotate(byDegrees: -16)
            tilt.translateX(by: -9, yBy: -10)
            tilt.concat()
            let shackle = NSBezierPath()
            shackle.move(to: NSPoint(x: 7.1, y: 8.6))
            shackle.line(to: NSPoint(x: 7.1, y: 7.4))
            shackle.appendArc(withCenter: NSPoint(x: 9, y: 7.4), radius: 1.9, startAngle: 180, endAngle: 0, clockwise: false)
            shackle.line(to: NSPoint(x: 10.9, y: 8.6))
            shackle.lineWidth = 1.2
            shackle.stroke()
            NSBezierPath(roundedRect: NSRect(x: 6, y: 8.4, width: 6, height: 4.6), xRadius: 1.2, yRadius: 1.2).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Blocking"
        rings[step] = image
        return image
    }

    /// Drawn on an 18-point square, y down, tilted 16° to the left about the lock's middle.
    private static func draw(locked: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            let tilt = NSAffineTransform()
            tilt.translateX(by: 9, yBy: 10)
            tilt.rotate(byDegrees: -16)
            tilt.translateX(by: -9, yBy: -10)
            tilt.concat()

            NSColor.black.set()
            let shackle = NSBezierPath()
            shackle.move(to: NSPoint(x: 6.3, y: locked ? 8.6 : 8.2))
            shackle.line(to: NSPoint(x: 6.3, y: 6.3))
            shackle.appendArc(withCenter: NSPoint(x: 9, y: 6.3), radius: 2.7, startAngle: 180, endAngle: 0, clockwise: false)
            shackle.line(to: NSPoint(x: 11.7, y: locked ? 8.6 : 8.2))
            shackle.lineWidth = 1.6
            shackle.lineCapStyle = .round
            shackle.stroke()

            let body = NSBezierPath(roundedRect: NSRect(x: 4, y: 8.2, width: 10, height: 7.6), xRadius: 2.3, yRadius: 2.3)
            if locked {
                body.fill()
                NSGraphicsContext.current?.compositingOperation = .clear
                NSBezierPath(ovalIn: NSRect(x: 7.65, y: 10.05, width: 2.7, height: 2.7)).fill()
                NSBezierPath(roundedRect: NSRect(x: 8.4, y: 11.6, width: 1.2, height: 2.5), xRadius: 0.5, yRadius: 0.5).fill()
            } else {
                body.lineWidth = 1.6
                body.stroke()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = locked ? "Blocking" : "Seawall"
        return image
    }
}
