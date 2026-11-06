import AppKit
import SwiftUI

struct FXConverterView: View {
    @Bindable var store: MarketStore
    let current: CurrencyQuote
    @State var historical = false
    @State var date = Date()
    @State private var amount = "1000"
    @State private var inverse = false
    @State private var copied = false
    private var key: String { Dates.day(date) }
    private var snapshot: FXSnapshot? { store.archive.snapshot(on: date) }
    private var quote: CurrencyQuote? { historical ? snapshot?.quote(current.code) : current }
    private var parsed: Decimal? { Money.parse(amount).flatMap { $0 >= 0 && $0 <= 1_000_000_000_000 ? $0 : nil } }
    private var result: Decimal? {
        guard let parsed, let quote, quote.price > 0 else { return nil }
        return inverse ? parsed / quote.price : parsed * quote.price
    }
    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 13) {
                Label(store.l10n("Быстрый обмен"), systemImage: "arrow.left.arrow.right").font(.system(size: 12, weight: .semibold))
                Picker(store.l10n("Курс для расчёта"), selection: $historical) {
                    Text(store.l10n("Сейчас")).tag(false)
                    Text(store.l10n("На выбранную дату")).tag(true)
                }.pickerStyle(.segmented)
                if historical {
                    HStack {
                        DatePicker(store.l10n("Дата"), selection: $date, in: ...Dates.calendar.date(byAdding: .day, value: 1, to: Dates.calendar.startOfDay(for: store.now))!.addingTimeInterval(-1), displayedComponents: .date)
                            .datePickerStyle(.field).environment(\.timeZone, Dates.calendar.timeZone)
                        Spacer(minLength: 8)
                        Button(store.l10n("Загрузить курс")) { Task { _ = try? await store.archive.fetch(date, force: true) } }
                            .buttonStyle(.bordered).disabled(store.archive.loadingDays.contains(key))
                    }.font(.system(size: 11))
                    if store.archive.loadingDays.contains(key) { ProgressView(store.l10n("Загрузка архива…")).controlSize(.small) }
                    if let error = store.archive.dateErrors[key] {
                        Text(error).font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    }
                    if let quote, let snapshot {
                        Text(store.l10n("На \(Dates.parse(snapshot.requestedDay).map { Dates.formatter("dd.MM.yyyy").string(from: $0) } ?? snapshot.requestedDay) · действует с \(quote.effectiveDate)"))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        Text(store.l10n("1 \(current.code) = \(Money.format(quote.price, digits: 6)) UZS · проверено \(Dates.display(snapshot.checkedAt))"))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    } else {
                        Text(snapshot == nil ? store.l10n("Выберите дату и загрузите официальный курс ЦБ.") : store.l10n("Для \(current.code) на эту дату нет опубликованного курса."))
                            .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                } else { Text(store.l10n("По курсу ЦБ")).font(.system(size: 11)).foregroundStyle(.secondary) }
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(inverse ? "UZS" : current.code).font(.system(size: 11)).foregroundStyle(.secondary)
                        TextField(store.l10n("Сумма"), text: $amount).textFieldStyle(.plain).font(.system(size: 23, weight: .medium, design: .rounded)).monospacedDigit()
                            .accessibilityLabel(store.l10n("Сумма в \(inverse ? "UZS" : current.code)"))
                    }
                    Button { inverse.toggle() } label: { Image(systemName: "arrow.left.arrow.right") }
                        .buttonStyle(QuietIconButton()).help(store.l10n("Поменять направление")).accessibilityLabel(store.l10n("Поменять направление обмена"))
                    VStack(alignment: .trailing, spacing: 5) {
                        Text(inverse ? current.code : "UZS").font(.system(size: 11)).foregroundStyle(.secondary)
                        Text(Money.format(result)).font(.system(size: 23, weight: .medium, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                    }.frame(maxWidth: .infinity, alignment: .trailing).accessibilityLabel(store.l10n("Результат конвертации"))
                }
                if parsed == nil { Text(store.l10n("Введите сумму от 0 до 1 000 000 000 000.")).font(.system(size: 11)).foregroundStyle(.orange) }
                HStack {
                    Text(store.l10n("Ориентировочно, без комиссий банка")).font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Button(copied ? store.l10n("Скопировано") : store.l10n("Копировать")) {
                        guard let result else { return }
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(Money.format(result) + " " + (inverse ? current.code : "UZS"), forType: .string)
                        copied = true
                    }.buttonStyle(.borderless).font(.system(size: 11)).disabled(result == nil)
                }
                if historical { Text(store.l10n("Выходной может использовать предыдущую публикацию. Это курс ЦБ, не предложение банка.")).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                if let error = store.archive.storageError { Text(error).font(.system(size: 11)).foregroundStyle(.orange) }
            }
        }.onChange(of: date) { _, _ in copied = false }
            .onChange(of: historical) { _, _ in copied = false }
            .onChange(of: amount) { _, _ in copied = false }
            .onChange(of: inverse) { _, _ in copied = false }
            .onChange(of: current.code) { _, _ in copied = false }
            .onChange(of: quote?.price) { _, _ in copied = false }
    }
}
