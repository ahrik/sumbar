import SwiftUI

struct BankComparisonView: View {
    @Bindable var store: MarketStore
    @State private var amount = "1000"
    @State private var showAll = false
    @State private var showSourceErrors = false
    @State private var favoritesOnly = false
    private var action: ExchangeAction { store.preferences.bankAction }
    private var channel: BankChannel { store.preferences.bankChannel }
    private var input: Decimal? { Money.parse(amount).flatMap { $0 >= 0 && $0 <= 1_000_000_000_000 ? $0 : nil } }
    private var rows: [BankRow] {
        BankComparison.rows(quotes: store.cache.bankQuotes ?? [], currency: store.selectedCurrency, channel: channel, action: action, amount: input, failedProviders: Set(store.bankErrors.keys), at: store.now)
            .filter { !favoritesOnly || store.preferences.favoriteBanks.contains($0.quote.bankID) }
    }
    private var eligible: [BankRow] { rows.filter(\.eligible) }
    private var codes: [String] { Array(Set((store.cache.bankQuotes ?? []).map(\.currency) + [store.selectedCurrency])).sorted() }
    private var visibleRows: [BankRow] { showAll ? rows : Array(rows.prefix(8)) }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Сравнение банков").font(.system(size: 20, weight: .semibold))
                    Text("Покупка и продажа к узбекскому суму").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Валюта", selection: $store.selectedCurrency) {
                    ForEach(codes, id: \.self) { Text($0).tag($0) }
                }.labelsHidden().frame(width: 80)
            }
            Picker("Операция", selection: $store.preferences.bankAction) {
                Text("Покупаю \(store.selectedCurrency)").tag(ExchangeAction.buy)
                Text("Продаю \(store.selectedCurrency)").tag(ExchangeAction.sell)
            }.pickerStyle(.segmented).labelsHidden()
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Сумма в \(store.selectedCurrency)").font(.system(size: 11)).foregroundStyle(.secondary)
                    TextField("1000", text: $amount).textFieldStyle(.roundedBorder).monospacedDigit().accessibilityLabel("Сумма валюты для сравнения")
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Способ обмена").font(.system(size: 11)).foregroundStyle(.secondary)
                    Picker("Способ обмена", selection: $store.preferences.bankChannel) {
                        ForEach(BankChannel.allCases) { Text($0.title).tag($0) }
                    }.labelsHidden().frame(maxWidth: .infinity)
                }
            }
            Toggle("Только избранные банки", isOn: $favoritesOnly).toggleStyle(.checkbox).font(.system(size: 12))
            if input == nil {
                warning("Введите сумму от 0 до 1 000 000 000 000. Сортировка по курсу сохранена, итог не рассчитан.")
            }
            if let best = eligible.first, let rate = best.rate {
                Surface {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label(eligible.count > 1 ? "Лучший из полученных курсов" : "Доступное предложение", systemImage: "checkmark.seal").font(.system(size: 11, weight: .medium)).foregroundStyle(SumbarDesign.blue)
                            Spacer()
                            if store.loadingBanks { ProgressView().controlSize(.mini) }
                        }
                        HStack(alignment: .firstTextBaseline) {
                            Text(Money.format(rate)).font(.system(size: 34, weight: .medium, design: .rounded)).monospacedDigit()
                            Text("сум / \(store.selectedCurrency)").font(.system(size: 11)).foregroundStyle(.secondary)
                            Spacer()
                        }
                        HStack {
                            Text(best.quote.bankName).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                            Spacer()
                            if let total = best.total { Text(Money.format(total) + " сум").font(.system(size: 14, weight: .medium)).monospacedDigit() }
                        }
                        if eligible.count == 1 {
                            Text("Для сравнения нужно предложение ещё одного банка.").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        if let bestTotal = best.total, let worstTotal = eligible.last?.total, eligible.count > 1 {
                            Text("Разница между крайними предложениями: \(Money.format(abs(bestTotal - worstTotal))) сум")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                }
            } else if store.loadingBanks {
                ProgressView("Загружаем курсы банков…").font(.system(size: 12)).frame(maxWidth: .infinity).padding(.vertical, 20)
            } else if rows.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "building.columns").font(.system(size: 28, weight: .light)).foregroundStyle(SumbarDesign.blue)
                    Text("Для этого способа данных пока нет").font(.system(size: 13, weight: .medium))
                    Text(favoritesOnly ? "Добавьте банк в избранное или выключите фильтр." : "Выберите другую валюту или способ обмена.").font(.system(size: 11)).foregroundStyle(.secondary)
                    Button("Обновить курсы банков") { Task { await store.refreshBanks() } }.buttonStyle(.bordered)
                }.frame(maxWidth: .infinity).padding(.vertical, 18)
            } else { warning("Нет данных для выбора лучшего курса. Сохранённые котировки показаны ниже с отметкой.") }
            HStack {
                Text("Предложения банков").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("\(eligible.count) в сравнении").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            LazyVStack(spacing: 0) {
                ForEach(visibleRows) { row in
                    bankRow(row).padding(.vertical, 13)
                    if row.id != visibleRows.last?.id { Divider() }
                }
            }
            if rows.count > 8 {
                Button(showAll ? "Показать первые 8" : "Показать все: \(rows.count)") { showAll.toggle() }
                    .buttonStyle(.bordered).frame(maxWidth: .infinity)
            }
            if !store.bankErrors.isEmpty {
                DisclosureGroup("Не обновились источники: \(store.bankErrors.count)", isExpanded: $showSourceErrors) {
                    ForEach(BankProviders.sources.filter { store.bankErrors[$0.id] != nil }, id: \.id) { source in
                        Text("\(source.name): \(store.bankErrors[source.id] ?? "")").font(.system(size: 11)).foregroundStyle(.orange).padding(.top, 5)
                    }
                }.font(.system(size: 11))
            }
            Text("Расчёт без комиссий. Отделения одного банка могут предлагать разные курсы. Наличие валюты, лимиты и итоговую цену уточняйте в банке. Время проверки и время публикации показаны отдельно; Bank.uz не сообщает время публикации каждого курса.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("Котировки старше 2 часов после проверки или 48 часов после известной публикации исключаются из сравнения. Данные источника с ошибкой тоже не участвуют.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
    private func bankRow(_ row: BankRow) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(row.quote.bankName).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                Spacer()
                Button { store.toggleBankFavorite(row.quote.bankID) } label: {
                    Image(systemName: store.preferences.favoriteBanks.contains(row.quote.bankID) ? "star.fill" : "star")
                }.buttonStyle(.borderless).accessibilityLabel("Избранный банк \(row.quote.bankName)")
                    .accessibilityValue(store.preferences.favoriteBanks.contains(row.quote.bankID) ? "В избранном" : "Не в избранном")
                Button { store.pinBank(row.quote.bankID) } label: { Image(systemName: "pin") }
                    .buttonStyle(.borderless).help("Показать этот курс в строке меню").accessibilityLabel("Закрепить курс \(row.quote.bankName)")
                if row.eligible, eligible.count > 1, row.rate == eligible.first?.rate {
                    Text("Лучший курс").font(.system(size: 11, weight: .semibold)).foregroundStyle(SumbarDesign.blue)
                } else if !row.eligible {
                    Text(row.rate == nil ? "Нет курса" : "Не в рейтинге").font(.system(size: 11)).foregroundStyle(.orange)
                }
            }
            HStack(alignment: .top, spacing: 14) {
                quoteColumn("Банк покупает", price: row.quote.buy)
                quoteColumn("Банк продаёт", price: row.quote.sell)
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(action == .buy ? "Вы заплатите, сум" : "Вы получите, сум").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(Money.format(row.total)).font(.system(size: 14, weight: .medium)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
                    if row.eligible, let total = row.total, let best = eligible.first?.total, total != best {
                        Text("На \(Money.format(abs(total - best))) \(action == .buy ? "больше" : "меньше")")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Link(row.quote.sourceName, destination: URL(string: row.quote.sourceURL)!)
                    Text("· проверено \(Dates.display(row.quote.observedAt))").foregroundStyle(.secondary)
                }
                Text(row.quote.publishedAt.map { "Публикация \(Dates.display($0)) · Ташкент" } ?? "Время публикации не указано")
                    .foregroundStyle(.secondary)
            }.font(.system(size: 11))
        }
    }
    private func quoteColumn(_ title: String, price: Decimal?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(Money.format(price)).font(.system(size: 13)).monospacedDigit()
        }
    }
    private func warning(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.circle").font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
    }
}
