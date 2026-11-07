import AppKit

@MainActor enum SumbarBrand {
    static func image(size: CGFloat, template: Bool = true) -> NSImage {
        guard let url = Bundle.module.url(forResource: "SumbarMark", withExtension: "pdf"),
              let image = NSImage(contentsOf: url) else {
            preconditionFailure("Missing Sumbar brand resource")
        }
        image.size = NSSize(width: size, height: size)
        image.isTemplate = template
        return image
    }
}
