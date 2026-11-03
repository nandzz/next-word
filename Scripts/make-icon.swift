import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    FileHandle.standardError.write("usage: swift Scripts/make-icon.swift <output.icns> [preview.png]\n".data(using: .utf8)!)
    exit(1)
}
let outputURL = URL(fileURLWithPath: arguments[1])
let previewURL = arguments.count >= 3 ? URL(fileURLWithPath: arguments[2]) : nil

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func squirclePath(in rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func sparklePath(center: CGPoint, radius: CGFloat, innerRatio: CGFloat = 0.24) -> CGPath {
    let tips = [
        CGPoint(x: center.x, y: center.y + radius),
        CGPoint(x: center.x + radius, y: center.y),
        CGPoint(x: center.x, y: center.y - radius),
        CGPoint(x: center.x - radius, y: center.y),
    ]
    let path = CGMutablePath()
    path.move(to: tips[0])
    for index in tips.indices {
        let from = tips[index]
        let to = tips[(index + 1) % tips.count]
        let control = CGPoint(
            x: center.x + (from.x + to.x - 2 * center.x) * innerRatio,
            y: center.y + (from.y + to.y - 2 * center.y) * innerRatio
        )
        path.addQuadCurve(to: to, control: control)
    }
    path.closeSubpath()
    return path
}

func iBeamPath(centerX: CGFloat, top: CGFloat, bottom: CGFloat, serif: CGFloat, neck: CGFloat) -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: centerX - serif, y: top))
    path.addCurve(
        to: CGPoint(x: centerX, y: top - neck),
        control1: CGPoint(x: centerX - serif * 0.3, y: top),
        control2: CGPoint(x: centerX, y: top - neck * 0.25)
    )
    path.addCurve(
        to: CGPoint(x: centerX + serif, y: top),
        control1: CGPoint(x: centerX, y: top - neck * 0.25),
        control2: CGPoint(x: centerX + serif * 0.3, y: top)
    )
    path.move(to: CGPoint(x: centerX, y: top - neck))
    path.addLine(to: CGPoint(x: centerX, y: bottom + neck))
    path.move(to: CGPoint(x: centerX - serif, y: bottom))
    path.addCurve(
        to: CGPoint(x: centerX, y: bottom + neck),
        control1: CGPoint(x: centerX - serif * 0.3, y: bottom),
        control2: CGPoint(x: centerX, y: bottom + neck * 0.25)
    )
    path.addCurve(
        to: CGPoint(x: centerX + serif, y: bottom),
        control1: CGPoint(x: centerX, y: bottom + neck * 0.25),
        control2: CGPoint(x: centerX + serif * 0.3, y: bottom)
    )
    return path
}

func drawIcon(in context: CGContext) {
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let radius: CGFloat = 185
    let shape = squirclePath(in: body, radius: radius)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
    context.addPath(shape)
    context.setFillColor(color(0x2A1A6E))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(shape)
    context.clip()

    let background = CGGradient(
        colorsSpace: space,
        colors: [color(0x1E1458), color(0x4B2AB8), color(0x8B3FE0), color(0xFF7A66)] as CFArray,
        locations: [0, 0.34, 0.6, 0.97]
    )!
    context.drawLinearGradient(
        background,
        start: CGPoint(x: body.minX, y: body.maxY),
        end: CGPoint(x: body.maxX, y: body.minY),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )

    let sheen = CGGradient(
        colorsSpace: space,
        colors: [color(0xFFFFFF, 0.20), color(0xFFFFFF, 0)] as CFArray,
        locations: [0, 1]
    )!
    context.drawRadialGradient(
        sheen,
        startCenter: CGPoint(x: 330, y: 960), startRadius: 0,
        endCenter: CGPoint(x: 330, y: 960), endRadius: 620,
        options: []
    )

    let warmGlow = CGGradient(
        colorsSpace: space,
        colors: [color(0xFFB199, 0.35), color(0xFFB199, 0)] as CFArray,
        locations: [0, 1]
    )!
    context.drawRadialGradient(
        warmGlow,
        startCenter: CGPoint(x: 900, y: 120), startRadius: 0,
        endCenter: CGPoint(x: 900, y: 120), endRadius: 420,
        options: []
    )

    let chips: [(CGFloat, CGFloat, CGFloat)] = [(560, 236, 0.30), (468, 184, 0.21), (376, 132, 0.13)]
    for (y, width, alpha) in chips {
        let rect = CGRect(x: 548, y: y - 30, width: width, height: 60)
        context.addPath(CGPath(roundedRect: rect, cornerWidth: 30, cornerHeight: 30, transform: nil))
        context.setFillColor(color(0xFFFFFF, alpha))
        context.fillPath()
    }

    let beam = iBeamPath(centerX: 410, top: 782, bottom: 242, serif: 112, neck: 66)
    context.saveGState()
    context.setShadow(offset: .zero, blur: 48, color: color(0xFFFFFF, 0.42))
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.setLineWidth(62)
    context.setStrokeColor(color(0xFFFFFF))
    context.addPath(beam)
    context.strokePath()
    context.restoreGState()

    context.saveGState()
    context.setShadow(offset: .zero, blur: 46, color: color(0xFFFFFF, 0.7))
    context.setFillColor(color(0xFFFFFF))
    context.addPath(sparklePath(center: CGPoint(x: 652, y: 724), radius: 104))
    context.fillPath()
    context.setFillColor(color(0xFFFFFF, 0.9))
    context.addPath(sparklePath(center: CGPoint(x: 792, y: 818), radius: 44))
    context.fillPath()
    context.restoreGState()

    context.restoreGState()

    context.saveGState()
    context.addPath(squirclePath(in: body.insetBy(dx: 1.5, dy: 1.5), radius: radius - 1.5))
    context.setStrokeColor(color(0xFFFFFF, 0.16))
    context.setLineWidth(3)
    context.strokePath()
    context.restoreGState()

}

func renderPNG(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    let graphics = NSGraphicsContext(bitmapImageRep: rep)!
    let context = graphics.cgContext
    context.interpolationQuality = .high
    context.setShouldAntialias(true)
    context.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
    let scale = CGFloat(pixels) / 1024
    context.scaleBy(x: scale, y: scale)
    drawIcon(in: context)
    graphics.flushGraphics()
    return rep.representation(using: .png, properties: [:])!
}

let fileManager = FileManager.default
let iconsetURL = fileManager.temporaryDirectory
    .appendingPathComponent("NextWord-\(UUID().uuidString).iconset")
try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 1 ? "" : "@2x"
        let name = "icon_\(points)x\(points)\(suffix).png"
        try renderPNG(pixels: points * scale).write(to: iconsetURL.appendingPathComponent(name))
    }
}

if let previewURL {
    try renderPNG(pixels: 512).write(to: previewURL)
}

try fileManager.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconsetURL.path, "-o", outputURL.path]
try iconutil.run()
iconutil.waitUntilExit()
try? fileManager.removeItem(at: iconsetURL)

guard iconutil.terminationStatus == 0 else {
    FileHandle.standardError.write("iconutil failed with status \(iconutil.terminationStatus)\n".data(using: .utf8)!)
    exit(iconutil.terminationStatus)
}
print("Wrote \(outputURL.path)")
