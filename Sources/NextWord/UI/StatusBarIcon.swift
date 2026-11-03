import AppKit

enum StatusBarIcon {
    @MainActor private static var cache: [Bool: NSImage] = [:]

    @MainActor
    static func image(active: Bool) -> NSImage {
        if let cached = cache[active] { return cached }
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            draw(active: active)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = active ? "NextWord" : "NextWord (off)"
        cache[active] = image
        return image
    }

    private static func draw(active: Bool) {
        NSColor.black.setStroke()
        NSColor.black.setFill()

        let stemX: CGFloat = 6.5
        let top: CGFloat = 15.5
        let bottom: CGFloat = 2.5
        let serif: CGFloat = 2.6
        let neck: CGFloat = 1.5

        let beam = NSBezierPath()
        beam.lineWidth = 1.5
        beam.lineCapStyle = .round
        beam.lineJoinStyle = .round

        beam.move(to: NSPoint(x: stemX - serif, y: top))
        beam.curve(
            to: NSPoint(x: stemX, y: top - neck),
            controlPoint1: NSPoint(x: stemX - serif * 0.35, y: top),
            controlPoint2: NSPoint(x: stemX, y: top - neck * 0.3)
        )
        beam.curve(
            to: NSPoint(x: stemX + serif, y: top),
            controlPoint1: NSPoint(x: stemX, y: top - neck * 0.3),
            controlPoint2: NSPoint(x: stemX + serif * 0.35, y: top)
        )
        beam.move(to: NSPoint(x: stemX, y: top - neck))
        beam.line(to: NSPoint(x: stemX, y: bottom + neck))
        beam.move(to: NSPoint(x: stemX - serif, y: bottom))
        beam.curve(
            to: NSPoint(x: stemX, y: bottom + neck),
            controlPoint1: NSPoint(x: stemX - serif * 0.35, y: bottom),
            controlPoint2: NSPoint(x: stemX, y: bottom + neck * 0.3)
        )
        beam.curve(
            to: NSPoint(x: stemX + serif, y: bottom),
            controlPoint1: NSPoint(x: stemX, y: bottom + neck * 0.3),
            controlPoint2: NSPoint(x: stemX + serif * 0.35, y: bottom)
        )
        beam.stroke()

        let large = sparkle(center: NSPoint(x: 13.0, y: 12.2), radius: 4.3)
        let small = sparkle(center: NSPoint(x: 15.6, y: 5.6), radius: 1.9)

        if active {
            large.fill()
            small.fill()
        } else {
            large.lineWidth = 1.0
            large.lineJoinStyle = .round
            large.stroke()
            NSGraphicsContext.current?.saveGraphicsState()
            NSColor.black.withAlphaComponent(0.45).setFill()
            small.fill()
            NSGraphicsContext.current?.restoreGraphicsState()
        }
    }

    private static func sparkle(center: NSPoint, radius: CGFloat, innerRatio: CGFloat = 0.26) -> NSBezierPath {
        let tips = [
            NSPoint(x: center.x, y: center.y + radius),
            NSPoint(x: center.x + radius, y: center.y),
            NSPoint(x: center.x, y: center.y - radius),
            NSPoint(x: center.x - radius, y: center.y),
        ]
        let path = NSBezierPath()
        path.move(to: tips[0])
        for index in tips.indices {
            let from = tips[index]
            let to = tips[(index + 1) % tips.count]
            let control = NSPoint(
                x: center.x + (from.x + to.x - 2 * center.x) * innerRatio,
                y: center.y + (from.y + to.y - 2 * center.y) * innerRatio
            )
            path.curve(to: to, controlPoint1: control, controlPoint2: control)
        }
        path.close()
        return path
    }
}
