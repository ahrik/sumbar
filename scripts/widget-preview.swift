import AppKit
import SwiftUI
import WidgetKit

/// Run with render-widgets.sh; gallery fixtures never enter the live data path.
@main enum WidgetPreview {
    @MainActor static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let uzbek = RateConfiguration(); uzbek.language = .uz
        let example = RateProvider.example()
        let saved = RateEntry(date: example.date.addingTimeInterval(7200), configuration: RateConfiguration(), result: example.result)
        let missing = RateEntry(date: Date(), configuration: RateConfiguration(), result: WidgetRateResult(snapshot: nil, failed: true))
        let variants: [(String, WidgetFamily, RateEntry, Bool, NSSize)] = [
            ("currency-small", .systemSmall, example, false, NSSize(width: 170, height: 170)),
            ("currency-medium", .systemMedium, example, false, NSSize(width: 360, height: 170)),
            ("rates-medium", .systemMedium, example, true, NSSize(width: 360, height: 170)),
            ("rates-large", .systemLarge, example, true, NSSize(width: 360, height: 376)),
            ("currency-uz", .systemSmall, RateProvider.example(uzbek), false, NSSize(width: 170, height: 170)),
            ("currency-saved", .systemSmall, saved, false, NSSize(width: 170, height: 170)),
            ("rates-empty", .systemMedium, missing, true, NSSize(width: 360, height: 170))
        ]
        for appearance in ["light", "dark"] {
            for (name, family, entry, list, size) in variants {
                let content = Group {
                    if list { RatesWidgetView(entry: entry, previewFamily: family) }
                    else { CurrencyWidgetView(entry: entry, previewFamily: family) }
                }
                .padding(16).frame(width: size.width, height: size.height)
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .environment(\.colorScheme, appearance == "dark" ? .dark : .light)
                let host = NSHostingView(rootView: content)
                host.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
                let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
                window.contentView = host
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.1))
                guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw MarketError.invalidData }
                host.cacheDisplay(in: host.bounds, to: bitmap)
                guard let png = bitmap.representation(using: .png, properties: [:]) else { throw MarketError.invalidData }
                try png.write(to: directory.appendingPathComponent("\(name)-\(appearance).png"))
                window.contentView = nil
            }
        }
        print("Rendered widget previews to \(directory.path)")
    }
}
