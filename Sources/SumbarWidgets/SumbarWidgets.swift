import AppIntents
import SwiftUI
import WidgetKit

enum WidgetCurrency: String, AppEnum {
    case usd = "USD", eur = "EUR", rub = "RUB", kzt = "KZT", cny = "CNY", gbp = "GBP"
    case chf = "CHF", jpy = "JPY", krw = "KRW", `try` = "TRY", aed = "AED", kgs = "KGS"
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Валюта"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .usd: "USD", .eur: "EUR", .rub: "RUB", .kzt: "KZT", .cny: "CNY", .gbp: "GBP",
        .chf: "CHF", .jpy: "JPY", .krw: "KRW", .try: "TRY", .aed: "AED", .kgs: "KGS"
    ]
}

enum WidgetLanguage: String, AppEnum {
    case system, ru, uz
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Язык"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .system: "Как в macOS", .ru: "Русский", .uz: "O‘zbekcha"
    ]
    var bundle: Bundle {
        guard self != .system, let path = Bundle.main.path(forResource: rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return .main }
        return bundle
    }
    func text(_ key: String) -> String { bundle.localizedString(forKey: key, value: key, table: "Localizable") }
}

struct RateConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Настроить курсы"
    static let description = IntentDescription("Выберите валюту и язык виджета Sumbar.")
    @Parameter(title: "Валюта", default: .usd) var currency: WidgetCurrency
    @Parameter(title: "Язык", default: .system) var language: WidgetLanguage
}

struct RateEntry: TimelineEntry {
    let date: Date
    let configuration: RateConfiguration
    let result: WidgetRateResult
    var saved: Bool { result.failed || result.snapshot?.isFresh(at: date) != true }
    var language: WidgetLanguage { configuration.language }
    var codes: [String] {
        let first = configuration.currency.rawValue
        return [first] + ["USD", "EUR", "RUB", "KZT", "CNY", "GBP"].filter { $0 != first }
    }
    func quote(_ code: String) -> CurrencyQuote? { result.snapshot?.quote(code, at: date) }
}

struct RateProvider: AppIntentTimelineProvider {
    static let store: WidgetRateStore = {
        let file = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Sumbar/widget-rates.json")
        let http = MarketHTTPClient()
        return WidgetRateStore(fileURL: file) { date in
            try await CBUProvider.currencies(date: date) { try await http.data($0) }
        }
    }()

    func placeholder(in context: Context) -> RateEntry { Self.example() }

    func snapshot(for configuration: RateConfiguration, in context: Context) async -> RateEntry {
        if context.isPreview { return Self.example(configuration) }
        return RateEntry(date: Date(), configuration: configuration,
                         result: WidgetRateResult(snapshot: await Self.store.cached(), failed: false))
    }

    func timeline(for configuration: RateConfiguration, in context: Context) async -> Timeline<RateEntry> {
        let result = await Self.store.refresh()
        let now = Date()
        var entries = [RateEntry(date: now, configuration: configuration, result: result)]
        // Include all expiration boundaries so cached prices never outlive their publication.
        var cursor = now
        while let change = result.snapshot?.nextChange(after: cursor) {
            entries.append(RateEntry(date: change, configuration: configuration, result: result))
            cursor = change
        }
        return Timeline(entries: entries, policy: .after(now.addingTimeInterval(30 * 60)))
    }

    /// Gallery data only. Never used as a fallback in an installed widget.
    static func example(_ configuration: RateConfiguration = RateConfiguration()) -> RateEntry {
        let now = Date()
        let quotes = zip(["USD", "EUR", "RUB", "KZT", "CNY", "GBP"], [12000, 13850, 148, 24, 1680, 15800]).map {
            CurrencyQuote(code: $0.0, name: $0.0, price: Decimal($0.1), change: -12,
                          effectiveDate: Dates.formatter("dd.MM.yyyy").string(from: now))
        }
        return RateEntry(date: now, configuration: configuration,
                         result: WidgetRateResult(snapshot: WidgetRateSnapshot(quotes: quotes, checkedAt: now), failed: false))
    }
}

struct WidgetHeader: View {
    let language: WidgetLanguage
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "chart.xyaxis.line").foregroundStyle(.blue)
            Text("Sumbar").fontWeight(.semibold)
            Spacer(minLength: 4)
            Text(language.text("ЦБ РУз")).foregroundStyle(.secondary)
        }.font(.system(size: 11))
    }
}

struct WidgetFooter: View {
    let entry: RateEntry
    var compact = false
    var body: some View {
        if let snapshot = entry.result.snapshot {
            HStack(spacing: 3) {
                if entry.saved { Image(systemName: "clock.badge.exclamationmark") }
                Text(entry.language.text(entry.saved ? (compact ? "Сохранено" : "Сохранённые данные") : "Проверено"))
                Text(Dates.display(snapshot.checkedAt))
            }
            .font(.system(size: 9)).foregroundStyle(entry.saved ? .orange : .secondary)
            .lineLimit(1).minimumScaleFactor(0.8)
        } else {
            Text(entry.language.text("Нет данных · проверьте сеть"))
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
}

struct CurrencyWidgetView: View {
    @Environment(\.widgetFamily) private var widgetFamily
    let entry: RateEntry
    var previewFamily: WidgetFamily? = nil
    private var family: WidgetFamily { previewFamily ?? widgetFamily }
    var body: some View {
        let code = entry.configuration.currency.rawValue
        let quote = entry.quote(code)
        VStack(alignment: .leading, spacing: 5) {
            WidgetHeader(language: entry.language)
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(code).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                    Text(Money.format(quote?.price))
                        .font(.system(size: family == .systemSmall ? 29 : 34, weight: .semibold, design: .rounded))
                        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                    Text(entry.language.text("UZS за единицу")).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                if family != .systemSmall {
                    Spacer()
                    VStack(alignment: .trailing, spacing: 8) { detail(quote) }
                }
            }
            if family == .systemSmall { detail(quote) }
            Spacer(minLength: 0)
            WidgetFooter(entry: entry, compact: family == .systemSmall)
        }
        .widgetURL(WidgetLink.url(currency: code))
        .containerBackground(.background, for: .widget)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func detail(_ quote: CurrencyQuote?) -> some View {
        if let quote {
            HStack(spacing: 3) {
                Image(systemName: quote.change < 0 ? "arrow.down.right" : quote.change > 0 ? "arrow.up.right" : "minus")
                Text((quote.change > 0 ? "+" : "") + Money.format(quote.change) + " UZS")
            }
            .font(.system(size: 11, weight: .medium)).monospacedDigit().foregroundStyle(.blue)
            if family != .systemSmall {
                Text(entry.language.text("Действует с") + " " + quote.effectiveDate)
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            } else {
                Text(quote.effectiveDate).font(.system(size: 9)).foregroundStyle(.secondary)
            }
        } else {
            Text(entry.language.text("Курс недоступен")).font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
}

struct RatesWidgetView: View {
    @Environment(\.widgetFamily) private var widgetFamily
    let entry: RateEntry
    var previewFamily: WidgetFamily? = nil
    private var family: WidgetFamily { previewFamily ?? widgetFamily }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeader(language: entry.language)
            if family == .systemLarge {
                Text(entry.language.text("Курсы валют")).font(.system(size: 21, weight: .semibold))
                Text(entry.language.text("UZS за единицу")).font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                ForEach(Array(entry.codes.prefix(6)), id: \.self) { code in
                    Link(destination: WidgetLink.url(currency: code)) { largeRow(code) }
                        .buttonStyle(.plain)
                    if code != entry.codes.prefix(6).last { Divider() }
                }
                Spacer(minLength: 0)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 7) {
                    ForEach(Array(entry.codes.prefix(4)), id: \.self) { code in
                        Link(destination: WidgetLink.url(currency: code)) {
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(alignment: .firstTextBaseline, spacing: 5) {
                                    Text(code).font(.system(size: 11)).foregroundStyle(.secondary)
                                    Text(Money.format(entry.quote(code)?.price))
                                        .font(.system(size: 15, weight: .semibold)).monospacedDigit()
                                }
                                Text(entry.quote(code)?.effectiveDate ?? "—").font(.system(size: 8)).foregroundStyle(.secondary)
                            }.lineLimit(1).minimumScaleFactor(0.7).frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.plain)
                    }
                }
                Spacer(minLength: 0)
                Text(entry.language.text("UZS за единицу")).font(.system(size: 9)).foregroundStyle(.secondary)
            }
            WidgetFooter(entry: entry)
        }
        .widgetURL(WidgetLink.url(currency: entry.configuration.currency.rawValue))
        .containerBackground(.background, for: .widget)
    }

    private func largeRow(_ code: String) -> some View {
        let quote = entry.quote(code)
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(code).font(.system(size: 13, weight: .semibold))
                Text(quote?.effectiveDate ?? "—").font(.system(size: 9)).foregroundStyle(.secondary)
            }
            Spacer()
            Text(Money.format(quote?.price)).font(.system(size: 19, weight: .medium)).monospacedDigit()
        }
    }
}

struct CurrencyWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "uz.sumbar.currency", intent: RateConfiguration.self, provider: RateProvider()) {
            CurrencyWidgetView(entry: $0)
        }
        .configurationDisplayName("Курс валюты")
        .description("Официальный курс выбранной валюты к суму и изменение за день.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct RatesWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "uz.sumbar.rates", intent: RateConfiguration.self, provider: RateProvider()) {
            RatesWidgetView(entry: $0)
        }
        .configurationDisplayName("Курсы валют")
        .description("Четыре или шесть курсов ЦБ. Выбранная валюта — первая в списке.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

#if !WIDGET_PREVIEW
@main
#endif
struct SumbarWidgetsBundle: WidgetBundle {
    var body: some Widget {
        CurrencyWidget()
        RatesWidget()
    }
}
