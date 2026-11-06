#if DEBUG
import AppKit
import SwiftUI

/// Local visual QA only: synthetic values never reach providers or the disk cache.
@MainActor enum DesignPreview {
    static func fixture() -> MarketStore {
        let store = MarketStore(inMemory: true)
        let now = Date()
        store.now = now
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
        store.archive.seedPreview((0...365).map { offset in
            let date = Dates.calendar.date(byAdding: .day, value: -offset, to: now)!
            let day = Dates.calendar.startOfDay(for: date)
            let weekday = Dates.calendar.component(.weekday, from: day)
            let effective = day.addingTimeInterval(weekday == 7 ? -86400 : weekday == 1 ? -2 * 86400 : 0)
            let effectiveOffset = Dates.calendar.dateComponents([.day], from: effective, to: Dates.calendar.startOfDay(for: now)).day!
            let quote = CurrencyQuote(code: "USD", name: "Доллар США", price: Decimal(12530 - effectiveOffset % 30 * 7), change: 0, effectiveDate: Dates.formatter("dd.MM.yyyy").string(from: effective), nameUz: "AQSH dollari")
            return FXSnapshot(requestedDay: Dates.day(day), checkedAt: now, quotes: [quote])
        })
        let instrument = Instrument(key: "DEMO", ticker: "DEMO", name: "Пример акции", kind: "stock", currency: "UZS", price: 589, changePercent: Decimal(string: "2.43")!, tradeDate: Dates.day())
        store.cache.instruments = [instrument]; store.selectedInstrumentID = instrument.id
        let prices: [Decimal] = [540, 548, 543, 560, 552, 568, 565, 575, 570, 582, 578, 589]
        let points = prices.enumerated().map { index, price in PricePoint(date: Dates.calendar.date(byAdding: .day, value: index * 2 - 24, to: now)!, price: price) }
        var detail = SecurityDetail(history: points, coupon: nil, faceValue: nil)
        detail.session = SecuritySession(date: Dates.day(now), open: 580, high: 592, low: 578, volume: 12345, turnover: 7200000, volumeUnit: "shares")
        detail.issuerName = "Пример эмитента"; detail.sector = "Synthetic sector"
        detail.disclosures = [IssuerDisclosure(title: "Пример раскрытия: квартальная отчётность", date: Dates.day(now), url: URL(string: "https://new.openinfo.uz/")!)]
        store.cache.details[instrument.id] = detail
        store.cache.bankQuotes = [
            BankQuote(bankID: "demo-a", bankName: "Пример банка A", currency: "USD", channel: .cash, buy: 12490, sell: 12550, provider: "ipak", sourceURL: BankProviders.sources[0].url, publishedAt: now, observedAt: now),
            BankQuote(bankID: "demo-b", bankName: "Пример банка B", currency: "USD", channel: .cash, buy: 12500, sell: 12570, provider: "kapital", sourceURL: BankProviders.sources[1].url, publishedAt: now, observedAt: now),
            BankQuote(bankID: "demo-c", bankName: "Пример банка C", currency: "USD", channel: .cash, buy: 12480, sell: 12590, provider: "bankuz", sourceURL: BankProviders.sources[2].url, publishedAt: nil, observedAt: now)
        ]
        store.alerts.draft = RateAlertDraft(threshold: "12500")
        for offset in [30, 20, 15, 11, 10, 9, 7, 5, 4, 2, 1, 0] {
            let checked = now.addingTimeInterval(-Double(offset) * 86400)
            for quote in store.cache.bankQuotes ?? [] {
                let sample = BankQuote(bankID: quote.bankID, bankName: quote.bankName, currency: quote.currency, channel: quote.channel, buy: (quote.buy ?? 0) + Decimal(offset * 3), sell: (quote.sell ?? 0) + Decimal(offset * 2), provider: quote.provider, sourceURL: quote.sourceURL, publishedAt: quote.publishedAt == nil ? nil : checked.addingTimeInterval(-3600), observedAt: checked)
                store.bankHistory.record([sample], provider: quote.provider, at: checked)
            }
        }
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
        let store = fixture(); store.language = .uz
        let cases: [(String, AnyView, CGFloat)] = [
            ("bank-history-uz", AnyView(BankHistoryView(store: store, quote: store.cache.bankQuotes![0])), 580),
            ("historical-converter-uz", AnyView(FXConverterView(store: store, current: store.currency!, historical: true, date: Date().addingTimeInterval(-6 * 86400))), 440),
            ("security-context-uz", AnyView(SecurityContextView(store: store, instrument: store.instrument!, detail: store.cache.details[store.instrument!.id]!)), 500),
            ("year-chart-uz", AnyView(PanelView(store: store, panelHeight: 760, panelWidth: 660, isDesignPreview: true, desktop: DesktopControls(), tab: 0, period: .year)), 760)
        ]
        for (name, content, height) in cases {
            let width: CGFloat = name == "year-chart-uz" ? 660 : 520
            let root = VStack(alignment: .leading, spacing: 12) {
                if name != "year-chart-uz" { Text(store.l10n("Демонстрационные данные")).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 18) }
                content
            }.frame(width: width, height: height).background(SumbarDesign.canvas).environment(\.locale, Locale(identifier: "uz")).environment(\.colorScheme, .light)
            let host = NSHostingView(rootView: root)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: .aqua)
            window.contentView = host; host.frame = NSRect(x: 0, y: 0, width: width, height: height)
            host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.15))
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
