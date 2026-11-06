#if DEBUG
import AppKit
import SwiftUI

/// Local visual QA only: synthetic values never reach providers or the disk cache.
@MainActor enum DesignPreview {
    static func fixture() -> MarketStore {
        let store = MarketStore(inMemory: true)
        let now = Date()
        store.cache.fxChecked = now; store.cache.stocksChecked = now
        store.cache.currencies = [
            CurrencyQuote(code: "USD", name: "Доллар США", price: 12530, change: Decimal(string: "24.50")!, effectiveDate: Dates.formatter("dd.MM.yyyy").string(from: now), nameUz: "AQSH dollari"),
            CurrencyQuote(code: "EUR", name: "Евро", price: 13690, change: -15, effectiveDate: Dates.day()),
            CurrencyQuote(code: "RUB", name: "Российский рубль", price: 138, change: 1, effectiveDate: Dates.day()),
            CurrencyQuote(code: "KZT", name: "Казахстанский тенге", price: Decimal(string: "25.34")!, change: 0, effectiveDate: Dates.day())
        ]
        let values: [Decimal] = [12450, 12420, 12480, 12460, 12500, Decimal(string: "12505.5")!, 12530]
        store.cache.currencyHistory["USD"] = values.enumerated().map { index, value in
            PricePoint(date: Dates.calendar.date(byAdding: .day, value: index - 6, to: now)!, price: value)
        }
        store.cache.observed["USD"] = (0...8).map { index in PricePoint(date: now.addingTimeInterval(Double(index - 8) * 900), price: 12530) }
        let instrument = Instrument(key: "DEMO", ticker: "DEMO", name: "Пример акции", kind: "stock", currency: "UZS", price: 589, changePercent: Decimal(string: "2.43")!, tradeDate: Dates.day())
        store.cache.instruments = [instrument]; store.selectedInstrumentID = instrument.id
        let prices: [Decimal] = [540, 548, 543, 560, 552, 568, 565, 575, 570, 582, 578, 589]
        let points = prices.enumerated().map { index, price in PricePoint(date: Dates.calendar.date(byAdding: .day, value: index * 2 - 24, to: now)!, price: price) }
        store.cache.details[instrument.id] = SecurityDetail(history: points, coupon: nil, faceValue: nil)
        store.cache.bankQuotes = [
            BankQuote(bankID: "demo-a", bankName: "Пример банка A", currency: "USD", channel: .cash, buy: 12490, sell: 12550, provider: "ipak", sourceURL: BankProviders.sources[0].url, publishedAt: now, observedAt: now),
            BankQuote(bankID: "demo-b", bankName: "Пример банка B", currency: "USD", channel: .cash, buy: 12500, sell: 12570, provider: "kapital", sourceURL: BankProviders.sources[1].url, publishedAt: now, observedAt: now),
            BankQuote(bankID: "demo-c", bankName: "Пример банка C", currency: "USD", channel: .cash, buy: 12480, sell: 12590, provider: "bankuz", sourceURL: BankProviders.sources[2].url, publishedAt: nil, observedAt: now)
        ]
        store.alerts.draft = RateAlertDraft(threshold: "12500")
        let rule = RateAlertRule(source: .cbu, currency: "USD", bankID: nil, bankName: nil, channel: .cash, action: .buy, comparison: .atOrBelow, threshold: 12500, notifyOnFirstMatch: false)
        _ = store.alerts.add(rule)
        return store
    }
    static func render(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, tab, dark, reduced, height, language) in [
            ("currencies-dark", 0, true, false, CGFloat(760), AppLanguage.ru),
            ("currencies-light", 0, false, false, CGFloat(760), .ru),
            ("banks-dark", 1, true, false, CGFloat(760), .ru),
            ("securities-dark", 2, true, false, CGFloat(760), .ru),
            ("settings-dark", 3, true, false, CGFloat(760), .ru),
            ("alerts-light", 4, false, false, CGFloat(760), .ru),
            ("alerts-uz", 4, true, false, CGFloat(760), .uz),
            ("banks-uz", 1, true, false, CGFloat(760), .uz),
            ("settings-uz", 3, false, false, CGFloat(760), .uz),
            ("currencies-uz", 0, false, false, CGFloat(760), .uz),
            ("compact-accessible", 0, true, true, CGFloat(610), .ru)
        ] {
            let store = fixture(); store.language = language
            let root = PanelView(store: store, panelHeight: height, isDesignPreview: true, desktop: DesktopControls(), notifications: LocalNotifications(), tab: tab, period: .week)
                .environment(\.colorScheme, dark ? .dark : .light)
                .environment(\.previewOpaqueMaterial, reduced)
            let host = NSHostingView(rootView: root)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: height), styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            window.contentView = host
            host.frame = NSRect(x: 0, y: 0, width: 520, height: height)
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.15))
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw MarketError.invalidData }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { throw MarketError.invalidData }
            try png.write(to: directory.appendingPathComponent(name + ".png"))
            window.contentView = nil
        }
        print("Rendered native design previews to \(directory.path)")
    }
}
#endif
