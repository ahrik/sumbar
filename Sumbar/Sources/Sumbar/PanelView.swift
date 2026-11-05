import SwiftUI
import Charts
import AppKit

struct PanelView: View {
    @Bindable var store: MarketStore
    @State private var tab = 0
    @State private var period = "Сегодня"
    @State private var stockPeriod = 30
    @State private var securityKind = "stock"
    @State private var search = ""
    @State private var amount = "1000"
    @State private var inverse = false
    @State private var quantity = "100"
    @State private var entry = ""
    @State private var target = ""
    @State private var fee = "0"
    private let accent = Color(red: 0.36, green: 0.65, blue: 1)
    private let panel = Color(red: 0.105, green: 0.11, blue: 0.12)
    var body: some View {
        VStack(spacing: 0) {
            header
            Picker("Раздел", selection: $tab) {
                Label("Валюты", systemImage: "arrow.left.arrow.right").tag(0)
                Label("Ценные бумаги", systemImage: "chart.line.uptrend.xyaxis").tag(1)
                Label("Настройки", systemImage: "slider.horizontal.3").tag(2)
            }.pickerStyle(.segmented).labelsHidden().padding(.horizontal, 22).padding(.bottom, 16)
            Divider().overlay(.white.opacity(0.05))
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if tab == 0 { currencies }
                    else if tab == 1 { securities }
                    else { settings }
                }.padding(22)
            }
            Divider()
            HStack {
                Circle().fill(statusColor).frame(width: 6, height: 6)
                Text(statusText).font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button { Task { await store.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(store.loading).help("Обновить данные")
                Button { NSApplication.shared.terminate(nil) } label: { Image(systemName: "power") }.help("Выйти")
            }.buttonStyle(.borderless).padding(.horizontal, 22).padding(.vertical, 12)
        }
        .frame(width: 490, height: 740)
        .background(panel).preferredColorScheme(.dark).tint(accent)
        .task { await store.loadCurrencyHistory() }
    }
    private var statusColor: Color {
        let date = tab == 1 ? store.cache.stocksChecked : store.cache.fxChecked
        let error = tab == 1 ? store.stocksError : store.fxError
        return error != nil || date == nil || Date().timeIntervalSince(date!) > Double(store.refreshMinutes * 120) ? .orange : .green
    }
    private var statusText: String {
        let date = tab == 1 ? store.cache.stocksChecked : store.cache.fxChecked
        return date.map { "Проверено \(Dates.display($0)) · Ташкент" } ?? "Ожидание данных"
    }
    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "chart.xyaxis.line").font(.system(size: 23, weight: .medium)).foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Sumbar").font(.system(size: 20, weight: .semibold))
                Text("Финансы Узбекистана").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            if store.loading { ProgressView().controlSize(.small) }
            Text("UZS").font(.system(size: 11, weight: .medium)).padding(.horizontal, 9).padding(.vertical, 5).background(.white.opacity(0.07), in: Capsule())
        }.padding(22)
    }
    private var currencies: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let error = store.fxError { notice(error) }
            if !store.cache.currencies.isEmpty {
                Picker("Валюта", selection: $store.selectedCurrency) {
                    ForEach(store.cache.currencies) { q in Text("\(q.code) · \(q.name)").tag(q.code) }
                }
            }
            if let q = store.currency {
                HStack(alignment: .firstTextBaseline) {
                    Text(Money.format(q.price)).font(.system(size: 36, weight: .medium, design: .rounded)).monospacedDigit()
                    Text("сум / \(q.code)").font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                }
                HStack {
                    changeLabel(q.change, suffix: " сум")
                    Spacer()
                    Text("ЦБ · действует с \(q.effectiveDate)").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Picker("Период", selection: $period) { Text("Сегодня").tag("Сегодня"); Text("7 дней").tag("7 дней") }.pickerStyle(.segmented)
                PriceChart(points: currencyPoints, intraday: period == "Сегодня", color: accent)
                Text(period == "Сегодня" ? "Наблюдения за сегодня. Курс ЦБ может не меняться весь день; запись идёт, пока Sumbar запущен." : "Официальные публикации ЦБ за последние 7 дней. Выходные не создают новые котировки.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let error = store.chartError { notice(error) }
                Divider()
                Text("Конвертер по курсу ЦБ").font(.system(size: 14, weight: .semibold))
                HStack {
                    field(inverse ? "Сумма в UZS" : "Сумма в \(q.code)", text: $amount)
                    Button { inverse.toggle() } label: { Image(systemName: "arrow.left.arrow.right") }.buttonStyle(.borderless).help("Изменить направление")
                }
                if let n = valid(amount) {
                    resultRow("Получится примерно", value: Money.format(inverse ? n / q.price : n * q.price) + (inverse ? " \(q.code)" : " сум"))
                } else { notice("Введите положительную сумму или 0.") }
                Text("Официальный курс — ориентир. Цена обмена банка и комиссии могут отличаться.").font(.system(size: 11)).foregroundStyle(.secondary)
                Link("Источник: Центральный банк Узбекистана", destination: URL(string: "https://cbu.uz/ru/arkhiv-kursov-valyut/")!).font(.system(size: 11))
                DisclosureGroup("Курсы коммерческих банков") {
                    Text("Прямой источник банковских курсов пока не подключён. Курс ЦБ не подставляется вместо покупки и продажи банка.").font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 8)
                    Link("Открыть курсы Ipak Yuli Bank", destination: URL(string: "https://ru.ipakyulibank.uz/physical/obmen-valyut")!).font(.system(size: 12))
                }.font(.system(size: 12))
            } else { empty("Нет сохранённых курсов", detail: "Подключитесь к интернету и нажмите обновление.") }
        }
    }
    private var currencyPoints: [PricePoint] {
        if period == "Сегодня" { return store.cache.observed[store.selectedCurrency, default: []].filter { Dates.calendar.isDateInToday($0.date) } }
        return store.cache.currencyHistory[store.selectedCurrency, default: []]
    }
    private var filtered: [Instrument] {
        store.cache.instruments.filter { i in
            i.kind == securityKind && (search.isEmpty || (i.ticker + " " + i.name).localizedCaseInsensitiveContains(search))
        }.sorted { a,b in
            if a.tradeDate != b.tradeDate { return (a.tradeDate ?? "") > (b.tradeDate ?? "") }
            return a.ticker < b.ticker
        }
    }
    private var securities: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let error = store.stocksError { notice(error) }
            Text("РФБ «Тошкент»").font(.system(size: 17, weight: .semibold))
            Text("Последние сохранённые цены закрытия. Обновление списка не означает новую сделку.").font(.system(size: 11)).foregroundStyle(.secondary)
            Picker("Тип бумаги", selection: $securityKind) { Text("Акции").tag("stock"); Text("Облигации").tag("bond") }.pickerStyle(.segmented)
                .onChange(of: securityKind) { _, _ in selectFirst() }
            TextField("Поиск по тикеру или компании", text: $search).textFieldStyle(.roundedBorder)
                .onChange(of: search) { _, _ in
                    if !filtered.contains(where: { $0.id == store.selectedInstrumentID }) { selectFirst() }
                }
            if !filtered.isEmpty {
                Picker("Бумага", selection: $store.selectedInstrumentID) {
                    Text("Выберите бумагу").tag(Optional<String>.none)
                    ForEach(filtered) { i in Text("\(i.ticker) · \(i.name)").tag(Optional(i.id)) }
                }.onChange(of: store.selectedInstrumentID) { _, _ in
                    entry = ""; target = ""
                    if let i = store.instrument { Task { await store.loadDetail(i) } }
                }
                if let i = store.instrument, i.kind == securityKind {
                    securityContent(i)
                }
            } else { empty("Бумаги не найдены", detail: store.cache.instruments.isEmpty ? "Обновите данные или проверьте подключение." : "Измените поисковый запрос.") }
            Link("Источник: UZSE через Finmind", destination: URL(string: "https://finmind.uz/developers")!).font(.system(size: 11))
        }
    }
    private func selectFirst() { store.selectedInstrumentID = filtered.first?.id }
    @ViewBuilder private func securityContent(_ i: Instrument) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(Money.format(i.price)).font(.system(size: 32, weight: .medium, design: .rounded)).monospacedDigit()
                Text(i.currency + " / шт.").font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                if let change = i.changePercent { changeLabel(change, suffix: "%") } else { Text("Изменение: —").font(.system(size: 11)).foregroundStyle(.secondary) }
            }
            Text("Торговая сессия: \(i.tradeDate ?? "нет сделок") · изменение к предыдущей сохранённой сессии").font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Picker("История", selection: $stockPeriod) { Text("Месяц").tag(30); Text("3 месяца").tag(90); Text("Год").tag(365) }.pickerStyle(.segmented)
            let cutoff = Dates.calendar.date(byAdding: .day, value: -stockPeriod, to: Date())!
            let history = store.cache.details[i.id]?.history.filter { $0.date >= cutoff } ?? []
            PriceChart(points: history, intraday: false, color: accent)
            if store.loadingChart { ProgressView("Загрузка истории…").controlSize(.small) }
            if let error = store.chartError { notice(error) }
            Text("Внутридневной ленты у подключённого источника нет. График показывает реальные торговые сессии.").font(.system(size: 11)).foregroundStyle(.secondary)
            Divider()
            Text("Калькулятор сделки").font(.system(size: 14, weight: .semibold))
            HStack { field("Количество, шт.", text: $quantity); field("Комиссия за сторону, %", text: $fee) }
            HStack {
                field("Цена покупки", text: $entry, prompt: Money.format(i.price))
                field("Цена продажи", text: $target, prompt: Money.format(i.price))
            }
            if let p = i.price, let count = valid(quantity), count == Decimal(NSDecimalNumber(decimal: count).int64Value), let buy = entry.isEmpty ? p : valid(entry), buy > 0, let sell = target.isEmpty ? p : valid(target), let f = valid(fee), f <= 100 {
                let calc = Money.investment(quantity: count, entry: buy, exit: sell, fee: f)
                resultRow("Покупка с комиссией", value: Money.format(calc.cost) + " " + i.currency)
                resultRow("Продажа после комиссии", value: Money.format(calc.proceeds) + " " + i.currency)
                resultRow("Результат сделки", value: Money.format(calc.profit) + " " + i.currency)
                if calc.cost > 0 { resultRow("Доходность сделки", value: Money.format(calc.profit / calc.cost * 100) + "%") }
            } else { notice("Нужны целое количество, положительная цена покупки и комиссия от 0 до 100%. Если цены котировки нет, расчёт недоступен.") }
            if let detail = store.cache.details[i.id], let face = detail.faceValue, let coupon = detail.coupon {
                resultRow("Годовой купон на одну бумагу", value: Money.format(face * coupon / 100) + " " + i.currency)
                Text("Номинал × ставка купона. Это не доходность к погашению.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Text("Сценарный расчёт без налогов, дивидендов и купонных выплат. Цена последней сделки не гарантирует исполнение новой заявки.").font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
    private var settings: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Обновление данных").font(.system(size: 17, weight: .semibold))
            Picker("Проверять каждые", selection: $store.refreshMinutes) { Text("15 минут").tag(15); Text("30 минут").tag(30); Text("Час").tag(60) }
            Text("Проверки продолжаются при закрытой панели, пока приложение работает в строке меню. Во сне и после выхода обновлений нет; после пробуждения данные проверяются снова.").font(.system(size: 12)).foregroundStyle(.secondary)
            Divider()
            Text("Хранение и источники").font(.system(size: 14, weight: .semibold))
            Text("Последние курсы, история и настройки сохраняются на этом Mac. Учётная запись не нужна. Для загрузки данных приложение обращается к ЦБ и Finmind.").font(.system(size: 12)).foregroundStyle(.secondary)
            Text("Данные Finmind предназначены для личного использования. Публичное распространение данных или их массовая загрузка требуют разрешения поставщика; лицензия кода не распространяется на котировки.").font(.system(size: 12)).foregroundStyle(.secondary)
            Link("Условия Finmind", destination: URL(string: "https://finmind.uz/developers#terms")!)
            if let error = store.storageError { notice(error) }
            Text("Sumbar 0.1 · открытый исходный код").font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
    private func valid(_ text: String) -> Decimal? { Money.parse(text).flatMap { $0 >= 0 && $0 <= Decimal(1_000_000_000_000) ? $0 : nil } }
    private func field(_ label: String, text: Binding<String>, prompt: String = "0") -> some View {
        VStack(alignment: .leading, spacing: 6) { Text(label).font(.system(size: 11)).foregroundStyle(.secondary); TextField(prompt, text: text).textFieldStyle(.roundedBorder).monospacedDigit() }
    }
    private func resultRow(_ title: String, value: String) -> some View {
        HStack { Text(title).foregroundStyle(.secondary); Spacer(); Text(value).monospacedDigit().fontWeight(.medium) }.font(.system(size: 12))
    }
    private func changeLabel(_ value: Decimal, suffix: String) -> some View {
        Label((value > 0 ? "+" : "") + Money.format(value) + suffix, systemImage: value < 0 ? "arrow.down.right" : value > 0 ? "arrow.up.right" : "minus").font(.system(size: 12, weight: .medium)).foregroundStyle(value < 0 ? Color.orange : accent)
    }
    private func notice(_ text: String) -> some View { Label(text, systemImage: "exclamationmark.circle").font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
    private func empty(_ title: String, detail: String) -> some View { ContentUnavailableView(title, systemImage: "chart.xyaxis.line", description: Text(detail)).frame(maxWidth: .infinity) }
}

struct PriceChart: View {
    let points: [PricePoint]; let intraday: Bool; let color: Color
    @State private var selected: Date?
    private var axisFormat: Date.FormatStyle {
        var format: Date.FormatStyle = intraday ? .dateTime.hour().minute() : .dateTime.day().month()
        format.timeZone = TimeZone(identifier: "Asia/Tashkent")!
        return format
    }
    private var nearest: PricePoint? { guard let selected else { return nil }; return points.min { abs($0.date.timeIntervalSince(selected)) < abs($1.date.timeIntervalSince(selected)) } }
    private var domain: ClosedRange<Double> {
        let low = points.map(\.value).min() ?? 0; let high = points.map(\.value).max() ?? 1
        let padding = max((high - low) * 0.15, max(abs(high) * 0.002, 0.01))
        return (low - padding)...(high + padding)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if points.isEmpty {
                ContentUnavailableView("Пока нет точек", systemImage: "chart.line.uptrend.xyaxis", description: Text(intraday ? "Первое наблюдение появится после обновления." : "Источник не вернул историю за этот период.")).frame(height: 140)
            } else {
                Chart {
                    ForEach(points) { point in
                        LineMark(x: .value("Время", point.date), y: .value("Цена", point.value)).foregroundStyle(color).interpolationMethod(.stepEnd)
                        if points.count == 1 { PointMark(x: .value("Время", point.date), y: .value("Цена", point.value)).foregroundStyle(color) }
                    }
                    if let point = nearest { RuleMark(x: .value("Время", point.date)).foregroundStyle(.secondary); PointMark(x: .value("Время", point.date), y: .value("Цена", point.value)).foregroundStyle(color) }
                }.chartYScale(domain: domain).chartXSelection(value: $selected)
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine().foregroundStyle(.white.opacity(0.05)); AxisValueLabel(format: axisFormat)
                    } }.chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) }
                    .frame(height: 150).accessibilityLabel("График цены, \(points.count) наблюдений, время Ташкента")
                if let point = nearest { Text("\(Dates.display(point.date)) · \(Money.format(point.price))").font(.system(size: 11)).foregroundStyle(.secondary) }
                else if points.count == 1 { Text("Одно наблюдение. Следующие появятся после проверок.").font(.system(size: 11)).foregroundStyle(.secondary) }
            }
        }.environment(\.timeZone, TimeZone(identifier: "Asia/Tashkent")!)
    }
}
