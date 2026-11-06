import SwiftUI

struct BankComparisonView: View {
    @Bindable var store: MarketStore
    @State private var amount = "1000"
    @State private var amountMode = ExchangeAmountMode.foreign
    @State private var showAll = false
    @State private var showSourceErrors = false
    @State private var favoritesOnly = false
    private var action: ExchangeAction { store.preferences.bankAction }
    private var channel: BankChannel { store.preferences.bankChannel }
    private var input: Decimal? { Money.parse(amount).flatMap { $0 >= 0 && $0 <= 1_000_000_000_000 ? $0 : nil } }
    private var rows: [BankRow] {
        BankComparison.rows(quotes: store.cache.bankQuotes ?? [], currency: store.selectedCurrency, channel: channel, action: action, amount: input, failedProviders: Set(store.bankErrors.keys), at: store.now)
            .filter { store.focusedBankID != nil || !favoritesOnly || store.preferences.favoriteBanks.contains($0.quote.bankID) }
            .filter { store.focusedBankID == nil || store.focusedBankID == $0.quote.bankID }
    }
    private var eligible: [BankRow] { rows.filter(\.eligible) }
    private var codes: [String] { Array(Set((store.cache.bankQuotes ?? []).map(\.currency) + [store.selectedCurrency])).sorted() }
    private var visibleRows: [BankRow] { showAll ? rows : Array(rows.prefix(8)) }
    private var resultUnit: String { amountMode == .uzs ? store.selectedCurrency : "UZS" }
    private var resultTitle: String {
        if amountMode == .uzs { return action == .buy ? store.l10n("Вы получите") : store.l10n("Нужно продать") }
        return action == .buy ? store.l10n("Вы заплатите") : store.l10n("Вы получите")
    }
    private func result(_ row: BankRow) -> Decimal? { amountMode.result(amount: input, rate: row.rate) }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.l10n("Сравнение банков")).font(.system(size: 20, weight: .semibold))
                    Text(store.l10n("Покупка и продажа к узбекскому суму")).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Picker(store.l10n("Валюта"), selection: $store.selectedCurrency) {
                    ForEach(codes, id: \.self) { Text($0).tag($0) }
                }.labelsHidden().frame(width: 80)
            }
            Picker(store.l10n("Операция"), selection: $store.preferences.bankAction) {
                Text(store.l10n("Покупаю \(store.selectedCurrency)")).tag(ExchangeAction.buy)
                Text(store.l10n("Продаю \(store.selectedCurrency)")).tag(ExchangeAction.sell)
            }.pickerStyle(.segmented).labelsHidden()
            Picker(store.l10n("Сумма для расчёта"), selection: $amountMode) {
                Text(store.l10n("В \(store.selectedCurrency)")).tag(ExchangeAmountMode.foreign)
                Text(action == .buy ? store.l10n("Бюджет в UZS") : store.l10n("Получить UZS")).tag(ExchangeAmountMode.uzs)
            }.pickerStyle(.segmented)
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(store.l10n("Сумма в \(amountMode == .uzs ? "UZS" : store.selectedCurrency)")).font(.system(size: 11)).foregroundStyle(.secondary)
                    TextField("1000", text: $amount).textFieldStyle(.roundedBorder).monospacedDigit().accessibilityLabel(store.l10n("Сумма для сравнения в \(amountMode == .uzs ? "UZS" : store.selectedCurrency)"))
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(store.l10n("Способ обмена")).font(.system(size: 11)).foregroundStyle(.secondary)
                    Picker(store.l10n("Способ обмена"), selection: $store.preferences.bankChannel) {
                        ForEach(BankChannel.allCases) { Text(store.l10n.literal($0.title)).tag($0) }
                    }.labelsHidden().frame(maxWidth: .infinity)
                }
            }
            Toggle(store.l10n("Только избранные банки"), isOn: $favoritesOnly).toggleStyle(.checkbox).font(.system(size: 12))
            if store.focusedBankID != nil {
                HStack {
                    Text(store.l10n("Банк из уведомления")).font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Button(store.l10n("Показать все банки")) { store.focusedBankID = nil; favoritesOnly = false }.buttonStyle(.borderless).font(.system(size: 11))
                }
            }
            if input == nil {
                warning(store.l10n("Введите сумму от 0 до 1 000 000 000 000. Сортировка по курсу сохранена, итог не рассчитан."))
            }
            if let best = eligible.first, let rate = best.rate {
                Surface {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label(eligible.count > 1 ? store.l10n("Лучший из полученных курсов") : store.l10n("Доступное предложение"), systemImage: "checkmark.seal").font(.system(size: 11, weight: .medium)).foregroundStyle(SumbarDesign.blue)
                            Spacer()
                            if store.loadingBanks { ProgressView().controlSize(.mini) }
                        }
                        HStack(alignment: .firstTextBaseline) {
                            Text(Money.format(rate)).font(.system(size: 34, weight: .medium, design: .rounded)).monospacedDigit()
                            Text(store.l10n("сум / \(store.selectedCurrency)")).font(.system(size: 11)).foregroundStyle(.secondary)
                            Spacer()
                        }
                        HStack {
                            Text(best.quote.bankName).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                            Spacer()
                            if let total = result(best) {
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text(resultTitle).font(.system(size: 11)).foregroundStyle(.secondary)
                                    Text(Money.format(total) + " " + resultUnit).font(.system(size: 14, weight: .medium)).monospacedDigit()
                                }
                            }
                        }
                        if eligible.count == 1 {
                            Text(store.l10n("Для сравнения нужно предложение ещё одного банка.")).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        if let bestTotal = result(best), let last = eligible.last, let worstTotal = result(last), eligible.count > 1 {
                            Text(store.l10n("Разница между крайними предложениями: \(Money.format(abs(bestTotal - worstTotal))) \(resultUnit)"))
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                }
            } else if store.loadingBanks {
                ProgressView(store.l10n("Загружаем курсы банков…")).font(.system(size: 12)).frame(maxWidth: .infinity).padding(.vertical, 20)
            } else if rows.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "building.columns").font(.system(size: 28, weight: .light)).foregroundStyle(SumbarDesign.blue)
                    Text(store.l10n("Для этого способа данных пока нет")).font(.system(size: 13, weight: .medium))
                    Text(favoritesOnly ? store.l10n("Добавьте банк в избранное или выключите фильтр.") : store.l10n("Выберите другую валюту или способ обмена.")).font(.system(size: 11)).foregroundStyle(.secondary)
                    Button(store.l10n("Обновить курсы банков")) { Task { await store.refreshBanks() } }.buttonStyle(.bordered)
                }.frame(maxWidth: .infinity).padding(.vertical, 18)
            } else { warning(store.l10n("Нет данных для выбора лучшего курса. Сохранённые котировки показаны ниже с отметкой.")) }
            HStack {
                Text(store.l10n("Предложения банков")).font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(store.l10n("\(eligible.count) в сравнении")).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            LazyVStack(spacing: 0) {
                ForEach(visibleRows) { row in
                    bankRow(row).padding(.vertical, 13)
                    if row.id != visibleRows.last?.id { Divider() }
                }
            }
            if rows.count > 8 {
                Button(showAll ? store.l10n("Показать первые 8") : store.l10n("Показать все: \(rows.count)")) { showAll.toggle() }
                    .buttonStyle(.bordered).frame(maxWidth: .infinity)
            }
            if !store.bankErrors.isEmpty {
                DisclosureGroup(store.l10n("Не обновились источники: \(store.bankErrors.count)"), isExpanded: $showSourceErrors) {
                    ForEach(BankProviders.sources.filter { store.bankErrors[$0.id] != nil }, id: \.id) { source in
                        Text("\(source.name): \(store.bankErrors[source.id] ?? "")").font(.system(size: 11)).foregroundStyle(.orange).padding(.top, 5)
                    }
                }.font(.system(size: 11))
            }
            Text(store.l10n("Расчёт без комиссий. Отделения одного банка могут предлагать разные курсы. Наличие валюты, лимиты и итоговую цену уточняйте в банке. Время проверки и время публикации показаны отдельно; Bank.uz не сообщает время публикации каждого курса."))
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text(store.l10n("Котировки старше 2 часов после проверки или 48 часов после известной публикации исключаются из сравнения. Данные источника с ошибкой тоже не участвуют."))
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
                }.buttonStyle(.borderless).accessibilityLabel(store.l10n("Избранный банк \(row.quote.bankName)"))
                    .accessibilityValue(store.preferences.favoriteBanks.contains(row.quote.bankID) ? store.l10n("В избранном") : store.l10n("Не в избранном"))
                Button { store.pinBank(row.quote.bankID) } label: { Image(systemName: "pin") }
                    .buttonStyle(.borderless).help(store.l10n("Показать этот курс в строке меню")).accessibilityLabel(store.l10n("Закрепить курс \(row.quote.bankName)"))
                Button { store.prepareAlert(bank: row.quote) } label: { Image(systemName: "bell") }
                    .buttonStyle(.borderless).help(store.l10n("Уведомление об этом курсе")).accessibilityLabel(store.l10n("Создать уведомление для \(row.quote.bankName)"))
                if row.eligible, eligible.count > 1, row.rate == eligible.first?.rate {
                    Text(store.l10n("Лучший курс")).font(.system(size: 11, weight: .semibold)).foregroundStyle(SumbarDesign.blue)
                } else if !row.eligible {
                    Text(row.rate == nil ? store.l10n("Нет курса") : store.l10n("Не в рейтинге")).font(.system(size: 11)).foregroundStyle(.orange)
                }
            }
            HStack(alignment: .top, spacing: 14) {
                quoteColumn(store.l10n("Банк покупает"), price: row.quote.buy)
                quoteColumn(store.l10n("Банк продаёт"), price: row.quote.sell)
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(resultTitle + ", " + resultUnit).font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(Money.format(result(row))).font(.system(size: 14, weight: .medium)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
                    if row.eligible, let total = result(row), let first = eligible.first, let best = result(first), total != best {
                        Text(store.l10n("Разница с лучшим: \(Money.format(abs(total - best))) \(resultUnit)"))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Link(store.l10n.literal(row.quote.sourceName), destination: URL(string: row.quote.sourceURL)!)
                    Text(store.l10n("· проверено \(Dates.display(row.quote.observedAt))")).foregroundStyle(.secondary)
                }
                Text(row.quote.publishedAt.map { store.l10n("Публикация \(Dates.display($0)) · Ташкент") } ?? store.l10n("Время публикации не указано"))
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
