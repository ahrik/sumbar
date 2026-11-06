import SwiftUI
import Charts

struct BankHistoryView: View {
    @Bindable var store: MarketStore
    let quote: BankQuote
    @Environment(\.dismiss) private var dismiss
    @State private var days = 7
    @State private var provider: String
    init(store: MarketStore, quote: BankQuote) {
        self.store = store; self.quote = quote; _provider = State(initialValue: quote.provider)
    }
    private var sources: [BankQuote] {
        var values = store.bankHistory.series.values.map(\.quote).filter { $0.bankID == quote.bankID && $0.currency == quote.currency && $0.channel == quote.channel }
        if !values.contains(where: { $0.provider == quote.provider }) { values.append(quote) }
        return values.sorted { $0.provider < $1.provider }
    }
    private var selected: BankQuote { sources.first { $0.provider == provider } ?? quote }
    private var points: [BankObservation] { store.bankHistory.observations(for: selected.id, days: days, ending: store.now) }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(store.l10n("История курсов банка")).font(.title3.weight(.semibold))
                Spacer()
                Button(store.l10n("Готово")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text(quote.bankName + " · " + quote.currency + " · " + store.l10n.literal(quote.channel.title)).font(.headline)
            Picker(store.l10n("Источник"), selection: $provider) {
                ForEach(sources, id: \.provider) { Text(store.l10n.literal($0.sourceName)).tag($0.provider) }
            }
            Picker(store.l10n("Период"), selection: $days) {
                Text(store.l10n("Неделя")).tag(7)
                Text(store.l10n("Месяц")).tag(31)
            }.pickerStyle(.segmented)
            Text(store.l10n("Локальные наблюдения · UZS за 1 \(quote.currency)")).font(.caption).foregroundStyle(.secondary)
            if points.isEmpty {
                ContentUnavailableView(store.l10n("История пока пуста"), systemImage: "clock", description: Text(store.l10n("Наблюдения появятся после успешного обновления курсов."))).frame(height: 190)
            } else {
                Chart(points) { point in
                    if let buy = point.buy {
                        PointMark(x: .value("Date", point.observedAt), y: .value("UZS", NSDecimalNumber(decimal: buy).doubleValue))
                            .foregroundStyle(by: .value("Side", store.l10n("Банк покупает")))
                            .symbol(by: .value("Side", store.l10n("Банк покупает")))
                    }
                    if let sell = point.sell {
                        PointMark(x: .value("Date", point.observedAt), y: .value("UZS", NSDecimalNumber(decimal: sell).doubleValue))
                            .foregroundStyle(by: .value("Side", store.l10n("Банк продаёт")))
                            .symbol(by: .value("Side", store.l10n("Банк продаёт")))
                    }
                }
                .chartXScale(domain: store.now.addingTimeInterval(-Double(days) * 86400)...store.now)
                .chartYScale(domain: .automatic(includesZero: false))
                .environment(\.timeZone, Dates.calendar.timeZone)
                .frame(height: 190)
                if let last = points.last {
                    Text(store.l10n("Последнее наблюдение: \(Dates.display(last.observedAt)) · Ташкент")).font(.caption)
                    HStack {
                        Text(store.l10n("Банк покупает") + ": " + Money.format(last.buy))
                        Spacer()
                        Text(store.l10n("Банк продаёт") + ": " + Money.format(last.sell))
                    }.font(.callout).monospacedDigit()
                    Text(last.publishedAt.map { store.l10n("Публикация \(Dates.display($0)) · Ташкент") } ?? store.l10n("Время публикации не указано")).font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(store.l10n("Сохраняются только успешные проверки при работающем приложении. Пропуски не заполняются; точки не соединяются. Источники и способы обмена учитываются отдельно.")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let url = URL(string: selected.sourceURL), url.scheme == "https" { Link(store.l10n.literal(selected.sourceName), destination: url).font(.caption) }
            if let error = store.bankHistory.storageError { Text(error).font(.caption).foregroundStyle(.orange) }
        }.padding(20).frame(width: 500).environment(\.locale, Locale(identifier: store.language.rawValue))
    }
}
