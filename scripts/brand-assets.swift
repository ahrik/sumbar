// Rebuild the vector logo and native PDF from one geometric master.
import AppKit
import CoreText

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let branding = root.appendingPathComponent("branding")
let resources = root.appendingPathComponent("Sources/Sumbar/Resources")

let ribbon = CGMutablePath()
ribbon.move(to: CGPoint(x: 97, y: 0))
ribbon.addLine(to: CGPoint(x: 43, y: 0))
ribbon.addCurve(to: CGPoint(x: 20, y: 11), control1: CGPoint(x: 33, y: 0), control2: CGPoint(x: 27, y: 3))
ribbon.addLine(to: CGPoint(x: 7, y: 25))
ribbon.addCurve(to: CGPoint(x: 17, y: 62), control1: CGPoint(x: -6, y: 38), control2: CGPoint(x: -1, y: 57))
ribbon.addLine(to: CGPoint(x: 50, y: 62))
ribbon.addLine(to: CGPoint(x: 33, y: 49))
ribbon.addCurve(to: CGPoint(x: 39, y: 30), control1: CGPoint(x: 23, y: 42), control2: CGPoint(x: 28, y: 30))
ribbon.addLine(to: CGPoint(x: 77, y: 30))
ribbon.addCurve(to: CGPoint(x: 85, y: 26), control1: CGPoint(x: 81, y: 30), control2: CGPoint(x: 83, y: 29))
ribbon.addLine(to: CGPoint(x: 100, y: 5))
ribbon.addCurve(to: CGPoint(x: 97, y: 0), control1: CGPoint(x: 102, y: 2), control2: CGPoint(x: 101, y: 0))
ribbon.closeSubpath()
let mark = CGMutablePath()
mark.addPath(ribbon)
mark.addPath(ribbon, transform: CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: 100, ty: 100))

func svgPath(_ path: CGPath) -> String {
    func point(_ p: CGPoint) -> String { String(format: "%.3f %.3f", locale: Locale(identifier: "en_US_POSIX"), Double(p.x), Double(p.y)) }
    var commands: [String] = []
    path.applyWithBlock { pointer in
        let element = pointer.pointee
        switch element.type {
        case .moveToPoint: commands.append("M" + point(element.points[0]))
        case .addLineToPoint: commands.append("L" + point(element.points[0]))
        case .addQuadCurveToPoint: commands.append("Q" + point(element.points[0]) + " " + point(element.points[1]))
        case .addCurveToPoint: commands.append("C" + (0..<3).map { point(element.points[$0]) }.joined(separator: " "))
        case .closeSubpath: commands.append("Z")
        @unknown default: fatalError("Unsupported path element")
        }
    }
    return commands.joined(separator: " ")
}

let font = NSFont.systemFont(ofSize: 76, weight: .bold)
let line = CTLineCreateWithAttributedString(NSAttributedString(string: "Sumbar", attributes: [.font: font]))
let lettering = CGMutablePath()
for run in CTLineGetGlyphRuns(line) as! [CTRun] {
    let runFont = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as! CTFont
    let count = CTRunGetGlyphCount(run)
    var glyphs = [CGGlyph](repeating: 0, count: count)
    var positions = [CGPoint](repeating: .zero, count: count)
    CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
    CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
    for index in 0..<count {
        if let path = CTFontCreatePathForGlyph(runFont, glyphs[index], nil) {
            lettering.addPath(path, transform: CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 142 + positions[index].x, ty: 97 - positions[index].y))
        }
    }
}
let width = Int(ceil(lettering.boundingBoxOfPath.maxX + 16))
let markData = svgPath(mark)
for (name, ink) in [("sumbar-logo.svg", "#182842"), ("sumbar-logo-dark.svg", "#F5F8FE"), ("sumbar-logo-adaptive.svg", "#182842")] {
    let style = name.contains("adaptive") ? "\n  <style>@media(prefers-color-scheme:dark){.wordmark{fill:#F5F8FE}}</style>" : ""
    let svg = """
    <svg xmlns="http://www.w3.org/2000/svg" width="\(width)" height="140" viewBox="0 0 \(width) 140" role="img" aria-label="Sumbar">\(style)
      <path fill="#2467E7" transform="translate(16 20)" d="\(markData)"/>
      <path class="wordmark" fill="\(ink)" d="\(svgPath(lettering))"/>
    </svg>
    """
    try (svg + "\n").write(to: branding.appendingPathComponent(name), atomically: true, encoding: .utf8)
}
let symbol = """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="-4 -4 108 108" role="img" aria-label="Sumbar">
  <path fill="#2467E7" d="\(markData)"/>
</svg>
"""
try (symbol + "\n").write(to: branding.appendingPathComponent("sumbar-mark.svg"), atomically: true, encoding: .utf8)
try (symbol + "\n").write(to: root.appendingPathComponent("web/assets/mark.svg"), atomically: true, encoding: .utf8)

var mediaBox = CGRect(x: -4, y: -4, width: 108, height: 108)
let pdfURL = resources.appendingPathComponent("SumbarMark.pdf")
guard let context = CGContext(pdfURL as CFURL, mediaBox: &mediaBox, nil) else { fatalError("Cannot create brand PDF") }
context.beginPDFPage(nil)
context.translateBy(x: 0, y: 100)
context.scaleBy(x: 1, y: -1)
context.addPath(mark)
context.setFillColor(NSColor.black.cgColor)
context.fillPath()
context.endPDFPage()
context.closePDF()
print("Updated SVG logos, website mark and native PDF resource.")
