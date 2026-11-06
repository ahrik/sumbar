import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
    NSColor(srgbRed: red / 255, green: green / 255, blue: blue / 255, alpha: 1)
}

func png(_ name: String, width: Int, height: Int, scale: Int = 1, draw: () -> Void) throws {
    let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width * scale, pixelsHigh: height * scale,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    image.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: image)
    NSGraphicsContext.current?.imageInterpolation = .high
    draw()
    NSGraphicsContext.restoreGraphicsState()
    try image.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
}

func label(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat, weight: NSFont.Weight = .regular, ink: NSColor) {
    (text as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: ink
    ])
}

try png("dmg-background.png", width: 640, height: 420, scale: 2) {
    color(244, 247, 253).setFill()
    NSRect(x: 0, y: 0, width: 640, height: 420).fill()
    label("Sumbar", x: 48, y: 337, size: 34, weight: .semibold, ink: color(25, 40, 65))
    label("Перетащите Sumbar в «Программы»", x: 49, y: 302, size: 16, ink: color(75, 92, 116))
    color(224, 233, 250).setFill()
    for x in [CGFloat(96), CGFloat(416)] {
        NSBezierPath(roundedRect: NSRect(x: x, y: 105, width: 128, height: 128), xRadius: 34, yRadius: 34).fill()
    }
    color(108, 132, 171).setStroke()
    let arrow = NSBezierPath()
    arrow.lineWidth = 3; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
    arrow.move(to: NSPoint(x: 280, y: 169)); arrow.line(to: NSPoint(x: 354, y: 169))
    arrow.move(to: NSPoint(x: 340, y: 183)); arrow.line(to: NSPoint(x: 354, y: 169)); arrow.line(to: NSPoint(x: 340, y: 155))
    arrow.stroke()
    label("Затем откройте Sumbar из папки «Программы».", x: 49, y: 47, size: 13, ink: color(75, 92, 116))
}

let iconset = output.appendingPathComponent("Sumbar.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let filename = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try png("Sumbar.iconset/" + filename, width: points, height: points, scale: scale) {
            let t = AffineTransform(scale: CGFloat(points) / 1024)
            (t as NSAffineTransform).concat()
            color(36, 103, 231).setFill()
            NSBezierPath(roundedRect: NSRect(x: 80, y: 80, width: 864, height: 864), xRadius: 210, yRadius: 210).fill()
            NSColor.white.withAlphaComponent(0.24).setStroke()
            let baseline = NSBezierPath()
            baseline.lineWidth = 18; baseline.lineCapStyle = .round
            baseline.move(to: NSPoint(x: 250, y: 290)); baseline.line(to: NSPoint(x: 250, y: 740))
            baseline.move(to: NSPoint(x: 250, y: 290)); baseline.line(to: NSPoint(x: 790, y: 290)); baseline.stroke()
            NSColor.white.setStroke()
            let chart = NSBezierPath()
            chart.lineWidth = 52; chart.lineCapStyle = .round; chart.lineJoinStyle = .round
            chart.move(to: NSPoint(x: 285, y: 395)); chart.line(to: NSPoint(x: 425, y: 545))
            chart.line(to: NSPoint(x: 555, y: 475)); chart.line(to: NSPoint(x: 755, y: 695)); chart.stroke()
            NSColor.white.setFill()
            NSBezierPath(ovalIn: NSRect(x: 712, y: 652, width: 86, height: 86)).fill()
        }
    }
}
