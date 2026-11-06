import SwiftUI
import Charts
import AppKit

struct PanelView: View {
    @Bindable var store: MarketStore
    var panelHeight: CGFloat = 760
    var panelWidth: CGFloat = 520
    var isDesignPreview = false
    var desktop: DesktopControls? = nil
    var notifications: LocalNotifications? = nil
    @State var tab = 0
    @State var period = FXPeriod.today
    @State private var stockPeriod = 30
    @State private var securityKind = "stock"
    @State private var search = ""
    @State private var quantity = "100"
    @State private var entry = ""
    @State private var target = ""
    @State private var fee = "0"
    @AppStorage("appearance") private var appearance = "system"
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.previewOpaqueMaterial) private var previewOpaque
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var theme: ColorScheme? { appearance == "dark" ? .dark : appearance == "light" ? .light : nil }
    var body: some View {
        VStack(spacing: 0) {
            header
            if tab < 3 { PanelTabs(selection: $tab, language: store.language).padding(.horizontal, 22).padding(.bottom, 14) }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if tab == 0 { currencies }
                    else if tab == 1 { BankComparisonView(store: store) }
                    else if tab == 2 { securities }
                    else if tab == 3 { settings }
                    else { AlertsView(store: store, notifications: notifications) }
                }.padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 22)
            }.scrollIndicators(.hidden)
            footer
        }
        .frame(width: panelWidth, height: panelHeight)
        .background {
            if reduceTransparency || previewOpaque { SumbarDesign.canvas }
            else { PopoverMaterial().overlay(SumbarDesign.canvas.opacity(0.72)) }
        }
        .tint(SumbarDesign.blue).preferredColorScheme(theme)
        .environment(\.locale, Locale(identifier: store.language.rawValue))
        .task { if !isDesignPreview { await store.loadCurrencyHistory() } }
        .onAppear { if !isDesignPreview { showStoredSelection() } }
        .onChange(of: store.panelTab) { _, _ in if !isDesignPreview { showStoredSelection() } }
        .onChange(of: tab) { _, value in if !isDesignPreview { store.panelTab = value } }
        .onChange(of: store.instrument?.kind) { _, kind in if let kind { securityKind = kind } }
        .onExitCommand { desktop?.hidePanel?() }
    }
    private func showStoredSelection() {
        tab = store.panelTab
        if let instrument = store.instrument { securityKind = instrument.kind }
        if tab == 2 { search = "" }
    }
    private var header: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(SumbarDesign.blue.opacity(0.12))
                Image(systemName: "chart.xyaxis.line").font(.system(size: 21, weight: .semibold)).foregroundStyle(SumbarDesign.blue)
            }.frame(width: 42, height: 42).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(tab == 3 ? store.l10n("Настройки") : tab == 4 ? store.l10n("Уведомления") : "Sumbar").font(.system(size: 19, weight: .semibold))
                Text(isDesignPreview ? store.l10n("Демонстрационные данные") : tab == 3 ? store.l10n("Ваше пространство финансов") : store.l10n("Узбекистан в цифрах")).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            if let desktop {
                Button { desktop.togglePanelPin?() } label: { Image(systemName: desktop.panelPinned ? "pin.fill" : "pin") }
                    .buttonStyle(QuietIconButton()).help(store.l10n("Панель поверх других окон"))
                    .accessibilityLabel(store.l10n("Закрепить панель"))
                    .accessibilityValue(desktop.panelPinned ? store.l10n("Закреплена") : store.l10n("Не закреплена"))
                    .keyboardShortcut("p", modifiers: [.command, .shift])
            }
            if tab >= 3 {
                Button(store.l10n("Готово")) { tab = 0 }.buttonStyle(.bordered).controlSize(.small)
            } else {
                Button { store.prepareAlert() } label: { Image(systemName: "bell") }
                    .buttonStyle(QuietIconButton()).help(store.l10n("Уведомления о курсе")).accessibilityLabel(store.l10n("Открыть уведомления о курсе"))
                Button { Task { await store.refresh() } } label: {
                    if store.loading { ProgressView().controlSize(.mini) }
                    else { Image(systemName: "arrow.clockwise") }
                }.buttonStyle(QuietIconButton()).disabled(store.loading).help(store.l10n("Обновить данные · ⌘R"))
                    .accessibilityLabel(store.l10n("Обновить данные")).keyboardShortcut("r", modifiers: .command)
                Button { tab = 3 } label: { Image(systemName: "slider.horizontal.3") }
                    .buttonStyle(QuietIconButton()).help(store.l10n("Настройки · ⌘,"))
                    .accessibilityLabel(store.l10n("Настройки")).keyboardShortcut(",", modifiers: .command)
            }
        }.padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 18)
    }
    private var footer: some View {
        HStack(spacing: 7) {
            Circle().fill(store.status(for: tab).isCurrent ? SumbarDesign.positive : Color.orange).frame(width: 5, height: 5)
            Text(store.loading ? store.l10n("Проверяем источники…") : store.l10n.status(store.status(for: tab)))
                .font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer()
            Text(store.l10n("Ташкент")).font(.system(size: 11)).foregroundStyle(.secondary)
            Divider().frame(height: 12).padding(.horizontal, 3)
            Button { NSApplication.shared.terminate(nil) } label: { Image(systemName: "power").font(.system(size: 11)) }
                .buttonStyle(.borderless).help(store.l10n("Выйти из Sumbar")).accessibilityLabel(store.l10n("Выйти из Sumbar"))
        }.padding(.horizontal, 22).padding(.vertical, 13)
            .background(SumbarDesign.canvas.opacity(0.65))
            .overlay(alignment: .top) { Rectangle().fill(SumbarDesign.separator).frame(height: 0.5) }
    }
    private var currencies: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let error = store.fxError { notice(error) }
            if !store.cache.currencies.isEmpty { quickCurrencies }
            if let q = store.currency {
                currencyHero(q)
                currencyChart
                FXConverterView(store: store, current: q)
                Button { tab = 1 } label: {
                    HStack { Label(store.l10n("Сравнить курсы банков"), systemImage: "building.columns"); Spacer(); Image(systemName: "chevron.right") }
                        .font(.system(size: 12, weight: .medium)).padding(.vertical, 8).contentShape(Rectangle())
                }.buttonStyle(.plain)
                sourceLink(store.l10n("Центральный банк Узбекистана"), url: "https://cbu.uz/ru/arkhiv-kursov-valyut/")
            } else {
                empty(store.l10n("Ваш валютный обзор"), detail: store.l10n("Курсы появятся после первой успешной проверки."), icon: "arrow.left.arrow.right")
            }
        }
    }
    private var quickCurrencies: some View {
        ScrollView(.horizontal) {
          HStack(spacing: 8) {
            ForEach(store.preferences.favoriteCurrencies, id: \.self) { code in
                if let quote = store.cache.currencies.first(where: { $0.code == code }) {
                    Button {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) { store.selectedCurrency = code }
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(code).font(.system(size: 12, weight: .semibold))
                            Text(Money.format(quote.price)).font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
                        }.frame(width: 80, alignment: .leading).padding(.horizontal, 13).padding(.vertical, 11)
                            .background(store.selectedCurrency == code ? SumbarDesign.blue.opacity(0.12) : SumbarDesign.subtle, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(store.selectedCurrency == code ? SumbarDesign.blue.opacity(0.35) : .clear))
                    }.buttonStyle(.plain).accessibilityLabel(store.l10n("\(store.currencyName(quote)), \(Money.format(quote.price)) сум"))
                        .accessibilityAddTraits(store.selectedCurrency == code ? .isSelected : [])
                }
            }
          }
        }.scrollIndicators(.hidden)
    }
    private func currencyHero(_ q: CurrencyQuote) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Menu {
                    ForEach(store.cache.currencies) { quote in Button("\(quote.code) — \(store.currencyName(quote))") { store.selectedCurrency = quote.code } }
                } label: { Text(store.currencyName(q)).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.tail) }
                    .menuStyle(.borderlessButton).frame(maxWidth: .infinity, alignment: .leading).help(store.l10n("Выбрать валюту"))
                Spacer()
                Text(store.l10n("Курс ЦБ")).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                Button { store.toggleCurrencyFavorite(q.code) } label: {
                    Image(systemName: store.preferences.favoriteCurrencies.contains(q.code) ? "star.fill" : "star")
                }.buttonStyle(.borderless).help(store.l10n("В избранное")).accessibilityLabel(store.l10n("Избранная валюта \(q.code)"))
                    .accessibilityValue(store.preferences.favoriteCurrencies.contains(q.code) ? store.l10n("В избранном") : store.l10n("Не в избранном"))
                Button { store.pinCurrency() } label: { Image(systemName: "pin") }
                    .buttonStyle(.borderless).help(store.l10n("Показать курс ЦБ в строке меню")).accessibilityLabel(store.l10n("Закрепить \(q.code) в строке меню"))
            }
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text(Money.format(q.price)).font(.system(size: 43, weight: .medium, design: .rounded)).tracking(-1.5).monospacedDigit()
                    .contentTransition(.numericText())
                Text(store.l10n("сум")).font(.system(size: 17)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                DeltaBadge(value: q.change, suffix: store.l10n(" сум"))
            }
            HStack {
                Text(store.l10n("за 1 \(q.code)"))
                Spacer()
                Text(store.l10n("Действует с \(q.effectiveDate)"))
            }.font(.system(size: 11)).foregroundStyle(.secondary)
        }.padding(.top, 3)
    }
    private var archiveSeries: FXArchiveSeries { store.archive.series(currency: store.selectedCurrency, period: period, ending: store.now) }
    private var currencyPoints: [PricePoint] {
        if period == .today { return store.cache.observed[store.selectedCurrency, default: []].filter { Dates.calendar.isDateInToday($0.date) } }
        let series = archiveSeries
        guard period == .week else { return series.points }
        let start = period.requestedDates(ending: store.now).first!.addingTimeInterval(-3 * 86400)
        var values: [Date: Decimal] = [:]
        for point in store.cache.currencyHistory[store.selectedCurrency, default: []] where point.date >= start && point.date <= store.now { values[point.date] = point.price }
        for point in series.points { values[point.date] = point.price }
        return values.map { PricePoint(date: $0.key, price: $0.value) }.sorted { $0.date < $1.date }
    }
    private var currencyChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(store.l10n("Динамика курса")).font(.system(size: 12, weight: .semibold))
                Spacer()
                ForEach(FXPeriod.allCases) { value in
                    periodButton(periodTitle(value), selected: period == value) { period = value }
                }
            }
            let series = archiveSeries
            let dates = period.requestedDates(ending: store.now)
            let range = period == .today ? nil : min(dates.first!, currencyPoints.first?.date ?? dates.first!)...store.now
            PriceChart(points: currencyPoints, intraday: period == .today, color: SumbarDesign.blue, unit: "UZS", language: store.language, pointsOnly: period != .today && (series.sampled || !series.isComplete || series.currencyCount != series.requestedCount), dateDomain: range)
            if period == .today {
                Text(store.l10n("Наблюдения за день. Официальный курс может оставаться неизменным.")).font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                Text(period.isSampled ? store.l10n("Недельные срезы. Промежуточные курсы не показаны.") : store.l10n("Официальные публикации. В выходные дата действия может повторяться."))
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text(store.l10n("Загружено срезов: \(series.loadedCount) из \(series.requestedCount)"))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                if store.archive.loadingRange {
                    HStack {
                        ProgressView(store.l10n("Загрузка архива…")).controlSize(.small)
                        Spacer()
                        Button(store.l10n("Остановить")) { store.archive.cancelRange() }.buttonStyle(.borderless).font(.system(size: 11))
                    }
                } else if !series.isComplete {
                    Button(store.l10n("Загрузить оставшееся")) { Task { await store.archive.loadRange(currency: store.selectedCurrency, period: period) } }.buttonStyle(.borderless).font(.system(size: 11))
                }
                if let error = store.archive.rangeError { notice(error) }
                if let error = store.archive.storageError { notice(error) }
            }
        }.padding(.vertical, 2)
            .task(id: store.selectedCurrency + period.rawValue + Dates.day(store.now)) {
                if !isDesignPreview, period != .today { await store.archive.loadRange(currency: store.selectedCurrency, period: period) }
            }
    }
    private func periodTitle(_ period: FXPeriod) -> String {
        switch period {
        case .today: store.l10n("День")
        case .week: store.l10n("Неделя")
        case .month: store.l10n("1М")
        case .quarter: store.l10n("3М")
        case .year: store.l10n("1Г")
        }
    }
    private var filtered: [Instrument] {
        store.cache.instruments.filter { i in
            i.kind == securityKind && (search.isEmpty || (i.ticker + " " + i.name).localizedCaseInsensitiveContains(search))
        }.sorted { a, b in
            if a.tradeDate != b.tradeDate { return (a.tradeDate ?? "") > (b.tradeDate ?? "") }
            return a.ticker < b.ticker
        }
    }
    private var securities: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let error = store.stocksError { notice(error) }
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.l10n("Рынок Узбекистана")).font(.system(size: 19, weight: .semibold))
                    Text(store.l10n("РФБ «Тошкент»")).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Text(store.l10n("По сессиям")).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    .padding(.horizontal, 10).padding(.vertical, 6).background(SumbarDesign.subtle, in: Capsule())
            }
            HStack {
                Picker(store.l10n("Тип бумаги"), selection: $securityKind) { Text(store.l10n("Акции")).tag("stock"); Text(store.l10n("Облигации")).tag("bond") }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 205)
                    .onChange(of: securityKind) { _, _ in if store.instrument?.kind != securityKind { selectFirst() } }
                Spacer()
                Text(store.l10n("\(filtered.count) бумаг")).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if !store.preferences.favoriteInstruments.isEmpty {
                Menu {
                    ForEach(store.preferences.favoriteInstruments, id: \.self) { id in
                        if let i = store.cache.instruments.first(where: { $0.id == id }) {
                            Button("\(i.ticker) · \(i.name)") { search = ""; store.selectedInstrumentID = i.id; securityKind = i.kind }
                        } else { Text(store.l10n("\(id) — недоступна")) }
                    }
                } label: { Label(store.l10n("Избранные бумаги"), systemImage: "star") }.font(.system(size: 12))
            }
            if let id = store.selectedInstrumentID, !store.cache.instruments.contains(where: { $0.id == id }) {
                notice(store.l10n("Выбранная бумага \(id) недоступна. Выберите другую из списка или обновите данные."))
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(store.l10n("Тикер или название компании"), text: $search).textFieldStyle(.plain)
                if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).accessibilityLabel(store.l10n("Очистить поиск")) }
            }.font(.system(size: 12)).padding(11).background(SumbarDesign.subtle, in: RoundedRectangle(cornerRadius: 10))
                .onChange(of: search) { _, _ in if !filtered.contains(where: { $0.id == store.selectedInstrumentID }) { selectFirst() } }
            if !filtered.isEmpty {
                Picker(store.l10n("Бумага"), selection: $store.selectedInstrumentID) {
                    Text(store.l10n("Выберите бумагу")).tag(Optional<String>.none)
                    if let id = store.selectedInstrumentID, !filtered.contains(where: { $0.id == id }) {
                        Text(store.l10n("\(id) — недоступна")).tag(Optional(id))
                    }
                    ForEach(filtered) { i in Text("\(i.ticker) · \(i.name)").tag(Optional(i.id)) }
                }.labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
                    .onChange(of: store.selectedInstrumentID) { _, _ in
                        entry = ""; target = ""
                        if let i = store.instrument, !isDesignPreview { Task { await store.loadDetail(i) } }
                    }
                if let i = store.instrument, i.kind == securityKind { securityContent(i) }
            } else { empty(store.l10n("Ничего не найдено"), detail: store.cache.instruments.isEmpty ? store.l10n("Котировки появятся после первой проверки.") : store.l10n("Попробуйте другой тикер или название."), icon: "magnifyingglass") }
            sourceLink(store.l10n("UZSE через Finmind"), url: "https://finmind.uz/developers")
        }
    }
    private func selectFirst() { store.selectedInstrumentID = filtered.first?.id }
    @ViewBuilder private func securityContent(_ i: Instrument) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(i.ticker).font(.system(size: 13, weight: .semibold))
                Spacer()
                Button { store.toggleInstrumentFavorite(i.id) } label: {
                    Label(store.l10n("Избранное"), systemImage: store.preferences.favoriteInstruments.contains(i.id) ? "star.fill" : "star")
                }.buttonStyle(.borderless)
                Button { store.pinInstrument(i.id) } label: { Image(systemName: "pin") }
                    .buttonStyle(.borderless).help(store.l10n("Показать закрытие в строке меню")).accessibilityLabel(store.l10n("Закрепить \(i.ticker) в строке меню"))
            }.font(.system(size: 11))
            HStack(alignment: .firstTextBaseline) {
                Text(Money.format(i.price)).font(.system(size: 38, weight: .medium, design: .rounded)).tracking(-1).monospacedDigit()
                Text(securityUnit(i)).font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                if let change = i.changePercent { DeltaBadge(value: change) }
                else { Text(store.l10n("Изменение: —")).font(.system(size: 11)).foregroundStyle(.secondary) }
            }
            Text(store.l10n("Сессия \(i.tradeDate ?? store.l10n("без сделок")) · к предыдущей сохранённой сессии"))
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Text(store.l10n("Цена закрытия")).font(.system(size: 12, weight: .semibold))
                Spacer()
                ForEach([30, 90, 365], id: \.self) { days in
                    periodButton(days == 30 ? store.l10n("1М") : days == 90 ? store.l10n("3М") : store.l10n("1Г"), selected: stockPeriod == days) { stockPeriod = days }
                }
            }
            let cutoff = Dates.calendar.date(byAdding: .day, value: -stockPeriod, to: Date())!
            let history = store.cache.details[i.id]?.history.filter { $0.date >= cutoff } ?? []
            PriceChart(points: history, intraday: false, color: SumbarDesign.blue, unit: securityUnit(i), language: store.language)
            if store.detailLoading.contains(i.id) { ProgressView(store.l10n("Загрузка истории…")).controlSize(.small) }
            if let error = store.securityHistoryErrors[i.id] {
                notice(error)
                Button(store.l10n("Повторить загрузку истории")) { Task { await store.loadDetail(i, force: true) } }
                    .buttonStyle(.borderless).font(.system(size: 11))
            }
            Text(store.l10n("Цены закрытия торговых сессий. Внутридневная лента не подключена.")).font(.system(size: 11)).foregroundStyle(.secondary)
            if let detail = store.cache.details[i.id] { SecurityContextView(store: store, instrument: i, detail: detail) }
            securityCalculator(i)
        }
    }
    private func securityUnit(_ instrument: Instrument) -> String {
        if instrument.kind == "stock" || store.cache.details[instrument.id]?.priceBasis == "amount_per_bond" { return instrument.currency + store.l10n(" / шт.") }
        if store.cache.details[instrument.id]?.priceBasis == "percent_of_par" { return store.l10n("% номинала") }
        return store.l10n("Единицы источника")
    }
    private func securityCalculator(_ i: Instrument) -> some View {
        Surface {
            VStack(alignment: .leading, spacing: 14) {
                Label(store.l10n("Сценарий сделки"), systemImage: "function").font(.system(size: 12, weight: .semibold))
                let price = store.cache.details[i.id]?.unitPrice(i.price, kind: i.kind) ?? (i.kind == "stock" ? i.price : nil)
                Text(store.l10n("Цены в \(i.currency) за бумагу")).font(.system(size: 11)).foregroundStyle(.secondary)
                HStack(spacing: 14) { field(store.l10n("Количество, шт."), text: $quantity); field(store.l10n("Комиссия за сторону, %"), text: $fee) }
                HStack(spacing: 14) {
                    field(store.l10n("Цена покупки"), text: $entry, prompt: Money.format(price))
                    field(store.l10n("Цена продажи"), text: $target, prompt: Money.format(price))
                }
                Divider()
                if let p = price, let count = valid(quantity), count == Decimal(NSDecimalNumber(decimal: count).int64Value), let buy = entry.isEmpty ? p : valid(entry), buy > 0, let sell = target.isEmpty ? p : valid(target), let f = valid(fee), f <= 100 {
                    let calc = Money.investment(quantity: count, entry: buy, exit: sell, fee: f)
                    resultRow(store.l10n("Покупка с комиссией"), value: Money.format(calc.cost) + " " + i.currency)
                    resultRow(store.l10n("Продажа после комиссии"), value: Money.format(calc.proceeds) + " " + i.currency)
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(store.l10n("Результат сделки")).font(.system(size: 11)).foregroundStyle(.secondary)
                            Text(Money.format(calc.profit) + " " + i.currency).font(.system(size: 23, weight: .medium, design: .rounded)).monospacedDigit()
                        }
                        Spacer()
                        if calc.cost > 0 { DeltaBadge(value: calc.profit / calc.cost * 100) }
                    }.padding(.top, 3)
                } else { notice(store.l10n("Укажите целое количество, цену покупки больше нуля и комиссию от 0 до 100%. Для расчёта нужна котировка.")) }
                if i.kind == "bond", price == nil { notice(store.l10n("Источник не подтвердил единицы котировки облигации. Расчёт суммы недоступен.")) }
                if let detail = store.cache.details[i.id], let face = detail.faceValue, let coupon = detail.coupon {
                    resultRow(store.l10n("Годовой купон на бумагу"), value: Money.format(face * coupon / 100) + " " + i.currency)
                    Text(store.l10n("Номинал × ставка купона, не доходность к погашению.")).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Text(store.l10n("Без налогов, дивидендов и купонов. Последняя цена не гарантирует цену новой сделки."))
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private var settings: some View {
        VStack(alignment: .leading, spacing: 18) {
            Picker(store.l10n("Язык интерфейса"), selection: $store.language) {
                ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
            }.font(.system(size: 12))
            OverviewSettingsView(store: store, desktop: desktop)
            Surface {
                VStack(alignment: .leading, spacing: 15) {
                    Label(store.l10n("Внешний вид"), systemImage: "circle.lefthalf.filled").font(.system(size: 13, weight: .semibold))
                    Picker(store.l10n("Оформление"), selection: $appearance) {
                        Text(store.l10n("Как в macOS")).tag("system"); Text(store.l10n("Светлое")).tag("light"); Text(store.l10n("Тёмное")).tag("dark")
                    }.pickerStyle(.segmented).labelsHidden()
                    Text(store.l10n("Материалы и контраст адаптируются к оформлению Mac и настройкам доступности.")).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Surface {
                VStack(alignment: .leading, spacing: 15) {
                    Label(store.l10n("Обновление данных"), systemImage: "arrow.clockwise").font(.system(size: 13, weight: .semibold))
                    Picker(store.l10n("Проверять каждые"), selection: $store.refreshMinutes) { Text(store.l10n("15 минут")).tag(15); Text(store.l10n("30 минут")).tag(30); Text(store.l10n("Час")).tag(60) }
                    Text(store.l10n("Проверяем источники даже при закрытой панели. Во сне и после выхода проверок нет; после пробуждения обновляем данные.")).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Label(store.l10n("Данные остаются на вашем Mac"), systemImage: "lock.shield").font(.system(size: 13, weight: .medium))
            Text(store.l10n("Курсы и настройки сохраняются локально. Без аккаунта и аналитики. Для загрузки приложение обращается к ЦБ, Finmind, Ipak Yuli Bank, Kapitalbank и Bank.uz.")).font(.system(size: 12)).foregroundStyle(.secondary)
            DisclosureGroup(store.l10n("Об источниках и условиях")) {
                Text(store.l10n("Finmind предназначен для личного использования. Для распространения котировок требуется разрешение поставщика; лицензия кода не распространяется на данные.")).font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 8)
                Link(store.l10n("Условия Finmind"), destination: URL(string: "https://finmind.uz/developers")!).font(.system(size: 11)).padding(.top, 5)
            }.font(.system(size: 12))
            if let error = store.storageError { notice(error) }
            HStack { Text("Sumbar \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")"); Spacer(); Text(store.l10n("Открытый исходный код")) }.font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
    private func valid(_ text: String) -> Decimal? { Money.parse(text).flatMap { $0 >= 0 && $0 <= Decimal(1_000_000_000_000) ? $0 : nil } }
    private func field(_ label: String, text: Binding<String>, prompt: String = "0") -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            TextField(prompt, text: text).textFieldStyle(.roundedBorder).font(.system(size: 13)).monospacedDigit().accessibilityLabel(label)
        }
    }
    private func resultRow(_ title: String, value: String) -> some View {
        HStack { Text(title).foregroundStyle(.secondary); Spacer(); Text(value).monospacedDigit().fontWeight(.medium) }.font(.system(size: 11))
    }
    private func periodButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 11, weight: selected ? .semibold : .regular)).padding(.horizontal, 10).padding(.vertical, 6)
                .foregroundStyle(selected ? Color.primary : Color.secondary)
                .background(selected ? SumbarDesign.subtle : .clear, in: Capsule())
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
    private func sourceLink(_ title: String, url: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.seal").foregroundStyle(.secondary)
            Link(title, destination: URL(string: url)!)
            Spacer()
            Image(systemName: "arrow.up.right").foregroundStyle(.secondary)
        }.font(.system(size: 11)).padding(.top, 1)
    }
    private func notice(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.circle").font(.system(size: 11)).foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true).padding(11).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
    private func empty(_ title: String, detail: String, icon: String) -> some View {
        VStack(spacing: 15) {
            Image(systemName: icon).font(.system(size: 32, weight: .light)).foregroundStyle(SumbarDesign.blue)
            Text(title).font(.system(size: 18, weight: .semibold))
            Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button(store.l10n("Проверить источники")) { Task { await store.refresh() } }.buttonStyle(.bordered).disabled(store.loading)
        }.frame(maxWidth: .infinity).padding(.vertical, 65)
    }
}

struct PriceChart: View {
    let points: [PricePoint]
    let intraday: Bool
    let color: Color
    var unit = "UZS"
    var language = AppLanguage.ru
    var pointsOnly = false
    var dateDomain: ClosedRange<Date>? = nil
    private var tr: L10n { L10n(language: language) }
    @State private var selected: Date?
    private var nearest: PricePoint? {
        guard let selected else { return nil }
        return points.min { abs($0.date.timeIntervalSince(selected)) < abs($1.date.timeIntervalSince(selected)) }
    }
    private var axisFormat: Date.FormatStyle {
        var format: Date.FormatStyle = intraday ? .dateTime.hour().minute() : .dateTime.day(.twoDigits).month(.twoDigits)
        if let dateDomain, dateDomain.upperBound.timeIntervalSince(dateDomain.lowerBound) > 200 * 86400 { format = format.year(.twoDigits) }
        format.locale = Locale(identifier: language.rawValue)
        format.timeZone = TimeZone(identifier: "Asia/Tashkent")!
        return format
    }
    private var domain: ClosedRange<Double> {
        let low = points.map(\.value).min() ?? 0; let high = points.map(\.value).max() ?? 1
        let padding = max((high - low) * 0.18, max(abs(high) * 0.002, 0.01))
        return (low - padding)...(high + padding)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if points.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "waveform.path").font(.system(size: 25, weight: .light)).foregroundStyle(color.opacity(0.7))
                    Text(tr("Здесь появится динамика")).font(.system(size: 12, weight: .medium))
                    Text(intraday ? tr("Ждём первое наблюдение за сегодня") : tr("Источник пока не вернул историю")).font(.system(size: 11)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).frame(height: 155)
            } else {
                Chart {
                    ForEach(points) { point in
                        if !pointsOnly {
                        AreaMark(x: .value(tr("Время"), point.date), yStart: .value(tr("Основание"), domain.lowerBound), yEnd: .value(tr("Цена"), point.value))
                            .foregroundStyle(LinearGradient(colors: [color.opacity(0.20), color.opacity(0.015)], startPoint: .top, endPoint: .bottom)).interpolationMethod(.stepEnd)
                        LineMark(x: .value(tr("Время"), point.date), y: .value(tr("Цена"), point.value))
                            .foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 2.1, lineCap: .round, lineJoin: .round)).interpolationMethod(.stepEnd)
                        }
                        if pointsOnly || points.count == 1 || point.id == points.last?.id {
                            PointMark(x: .value(tr("Время"), point.date), y: .value(tr("Цена"), point.value)).foregroundStyle(color).symbolSize(25)
                        }
                    }
                    if let point = nearest {
                        RuleMark(x: .value(tr("Время"), point.date)).foregroundStyle(Color.secondary.opacity(0.4)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        PointMark(x: .value(tr("Время"), point.date), y: .value(tr("Цена"), point.value)).foregroundStyle(color).symbolSize(40)
                    }
                }.chartYScale(domain: domain).chartXSelection(value: $selected).modifier(ChartDateDomain(range: dateDomain))
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 3)) { value in
                            AxisValueLabel(anchor: value.index == 0 ? .topLeading : value.index == value.count - 1 ? .topTrailing : .top) {
                                if let date = value.as(Date.self) { Text(date, format: axisFormat).font(.system(size: 11)) }
                            }
                        }
                    }.chartYAxis {
                        AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 4])).foregroundStyle(SumbarDesign.separator)
                            AxisValueLabel().font(.system(size: 11))
                        }
                    }.frame(height: 140)
                    .accessibilityLabel(tr("График цены в \(unit), \(points.count) наблюдений, время Ташкента"))
                HStack {
                    if let point = nearest { Text("\(Dates.display(point.date))  ·  \(Money.format(point.price)) \(unit)") }
                    else if points.count == 1 { Text(tr("Одно наблюдение. Новые появятся после проверок.")) }
                    else { Text(tr("\(points.count) наблюдений")); Spacer(); Text(unit) }
                }.font(.system(size: 11)).foregroundStyle(.secondary).frame(height: 14)
            }
        }.environment(\.timeZone, TimeZone(identifier: "Asia/Tashkent")!)
    }
}

private struct ChartDateDomain: ViewModifier {
    let range: ClosedRange<Date>?
    @ViewBuilder func body(content: Content) -> some View {
        if let range { content.chartXScale(domain: range) } else { content }
    }
}
