import SwiftUI
import Charts
import AppKit

struct PanelView: View {
    @Bindable var store: MarketStore
    var panelHeight: CGFloat = 760
    var isDesignPreview = false
    @State var tab = 0
    @State var period = "Сегодня"
    @State private var stockPeriod = 30
    @State private var securityKind = "stock"
    @State private var search = ""
    @State private var amount = "1000"
    @State private var inverse = false
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
            if tab != 3 { PanelTabs(selection: $tab).padding(.horizontal, 22).padding(.bottom, 14) }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if tab == 0 { currencies }
                    else if tab == 1 { BankComparisonView(store: store) }
                    else if tab == 2 { securities }
                    else { settings }
                }.padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 22)
            }.scrollIndicators(.hidden)
            footer
        }
        .frame(width: 520, height: panelHeight)
        .background {
            if reduceTransparency || previewOpaque { SumbarDesign.canvas }
            else { PopoverMaterial().overlay(SumbarDesign.canvas.opacity(0.72)) }
        }
        .tint(SumbarDesign.blue).preferredColorScheme(theme)
        .task { if !isDesignPreview { await store.loadCurrencyHistory() } }
    }
    private var checked: Date? {
        if tab == 1 { return store.cache.bankQuotes?.map(\.observedAt).max() }
        return tab == 2 ? store.cache.stocksChecked : store.cache.fxChecked
    }
    private var isStale: Bool {
        let error = tab == 1 ? (store.bankErrors.isEmpty ? nil : "Ошибка источника") : tab == 2 ? store.stocksError : store.fxError
        return error != nil || checked == nil || Date().timeIntervalSince(checked!) > Double(store.refreshMinutes * 120)
    }
    private var header: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(SumbarDesign.blue.opacity(0.12))
                Image(systemName: "chart.xyaxis.line").font(.system(size: 21, weight: .semibold)).foregroundStyle(SumbarDesign.blue)
            }.frame(width: 42, height: 42).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(tab == 3 ? "Настройки" : "Sumbar").font(.system(size: 19, weight: .semibold))
                Text(isDesignPreview ? "Демонстрационные данные" : tab == 3 ? "Ваше пространство финансов" : "Узбекистан в цифрах").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            if tab == 3 {
                Button("Готово") { tab = 0 }.buttonStyle(.bordered).controlSize(.small)
            } else {
                Button { Task { await store.refresh() } } label: {
                    if store.loading { ProgressView().controlSize(.mini) }
                    else { Image(systemName: "arrow.clockwise") }
                }.buttonStyle(QuietIconButton()).disabled(store.loading).help("Обновить данные · ⌘R")
                    .accessibilityLabel("Обновить данные").keyboardShortcut("r", modifiers: .command)
                Button { tab = 3 } label: { Image(systemName: "slider.horizontal.3") }
                    .buttonStyle(QuietIconButton()).help("Настройки · ⌘,")
                    .accessibilityLabel("Настройки").keyboardShortcut(",", modifiers: .command)
            }
        }.padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 18)
    }
    private var footer: some View {
        HStack(spacing: 7) {
            Circle().fill(isStale ? Color.orange : SumbarDesign.positive).frame(width: 5, height: 5)
            Text(store.loading ? "Проверяем источники…" : checked.map { "Проверено \(Dates.display($0))" } ?? "Ожидание данных")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer()
            Text("Ташкент").font(.system(size: 11)).foregroundStyle(.secondary)
            Divider().frame(height: 12).padding(.horizontal, 3)
            Button { NSApplication.shared.terminate(nil) } label: { Image(systemName: "power").font(.system(size: 11)) }
                .buttonStyle(.borderless).help("Выйти из Sumbar").accessibilityLabel("Выйти из Sumbar")
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
                converter(q)
                Button { tab = 1 } label: {
                    HStack { Label("Сравнить курсы банков", systemImage: "building.columns"); Spacer(); Image(systemName: "chevron.right") }
                        .font(.system(size: 12, weight: .medium)).padding(.vertical, 8).contentShape(Rectangle())
                }.buttonStyle(.plain)
                sourceLink("Центральный банк Узбекистана", url: "https://cbu.uz/ru/arkhiv-kursov-valyut/")
            } else {
                empty("Ваш валютный обзор", detail: "Курсы появятся после первой успешной проверки.", icon: "arrow.left.arrow.right")
            }
        }
    }
    private var quickCurrencies: some View {
        HStack(spacing: 8) {
            ForEach(["USD", "EUR", "RUB", "KZT"], id: \.self) { code in
                if let quote = store.cache.currencies.first(where: { $0.code == code }) {
                    Button {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) { store.selectedCurrency = code }
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(code).font(.system(size: 12, weight: .semibold))
                            Text(Money.format(quote.price)).font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 13).padding(.vertical, 11)
                            .background(store.selectedCurrency == code ? SumbarDesign.blue.opacity(0.12) : SumbarDesign.subtle, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(store.selectedCurrency == code ? SumbarDesign.blue.opacity(0.35) : .clear))
                    }.buttonStyle(.plain).accessibilityLabel("\(quote.name), \(Money.format(quote.price)) сум")
                        .accessibilityAddTraits(store.selectedCurrency == code ? .isSelected : [])
                }
            }
        }
    }
    private func currencyHero(_ q: CurrencyQuote) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Menu {
                    ForEach(store.cache.currencies) { quote in Button("\(quote.code) — \(quote.name)") { store.selectedCurrency = quote.code } }
                } label: { Text(q.name).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.tail) }
                    .menuStyle(.borderlessButton).frame(maxWidth: .infinity, alignment: .leading).help("Выбрать валюту")
                Spacer()
                Text("Курс ЦБ").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text(Money.format(q.price)).font(.system(size: 43, weight: .medium, design: .rounded)).tracking(-1.5).monospacedDigit()
                    .contentTransition(.numericText())
                Text("сум").font(.system(size: 17)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                DeltaBadge(value: q.change, suffix: " сум")
            }
            HStack {
                Text("за 1 \(q.code)")
                Spacer()
                Text("Действует с \(q.effectiveDate)")
            }.font(.system(size: 11)).foregroundStyle(.secondary)
        }.padding(.top, 3)
    }
    private var currencyPoints: [PricePoint] {
        if period == "Сегодня" { return store.cache.observed[store.selectedCurrency, default: []].filter { Dates.calendar.isDateInToday($0.date) } }
        return store.cache.currencyHistory[store.selectedCurrency, default: []]
    }
    private var currencyChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Динамика курса").font(.system(size: 12, weight: .semibold))
                Spacer()
                periodButton("День", selected: period == "Сегодня") { period = "Сегодня" }
                periodButton("Неделя", selected: period == "7 дней") { period = "7 дней" }
            }
            PriceChart(points: currencyPoints, intraday: period == "Сегодня", color: SumbarDesign.blue, unit: "UZS")
            Text(period == "Сегодня" ? "Наблюдения за день. Официальный курс может оставаться неизменным." : "Официальные публикации за 7 дней. В выходные новых значений может не быть.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let error = store.chartError { notice(error) }
        }.padding(.vertical, 2)
    }
    private func converter(_ q: CurrencyQuote) -> some View {
        Surface {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Label("Быстрый обмен", systemImage: "arrow.left.arrow.right").font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text("По курсу ЦБ").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(inverse ? "UZS" : q.code).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                        TextField("Сумма", text: $amount).textFieldStyle(.plain).font(.system(size: 23, weight: .medium, design: .rounded)).monospacedDigit()
                            .accessibilityLabel(inverse ? "Сумма в сумах" : "Сумма в \(q.code)")
                    }
                    Button { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { inverse.toggle() } } label: { Image(systemName: "arrow.left.arrow.right") }
                        .buttonStyle(QuietIconButton()).help("Поменять направление").accessibilityLabel("Поменять направление обмена")
                    VStack(alignment: .trailing, spacing: 5) {
                        Text(inverse ? q.code : "UZS").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                        if let n = valid(amount) {
                            Text(Money.format(inverse ? n / q.price : n * q.price)).font(.system(size: 23, weight: .medium, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                        } else { Text("—").font(.system(size: 23)).foregroundStyle(.secondary) }
                    }.frame(maxWidth: .infinity, alignment: .trailing).accessibilityLabel("Результат конвертации")
                }
                if valid(amount) == nil { notice("Введите сумму от 0 до 1 000 000 000 000.") }
                Text("Ориентировочно, без комиссий банка").font(.system(size: 11)).foregroundStyle(.secondary)
            }
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
                    Text("Рынок Узбекистана").font(.system(size: 19, weight: .semibold))
                    Text("РФБ «Тошкент»").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Text("По сессиям").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    .padding(.horizontal, 10).padding(.vertical, 6).background(SumbarDesign.subtle, in: Capsule())
            }
            HStack {
                Picker("Тип бумаги", selection: $securityKind) { Text("Акции").tag("stock"); Text("Облигации").tag("bond") }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 205)
                    .onChange(of: securityKind) { _, _ in selectFirst() }
                Spacer()
                Text("\(filtered.count) бумаг").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Тикер или название компании", text: $search).textFieldStyle(.plain)
                if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).accessibilityLabel("Очистить поиск") }
            }.font(.system(size: 12)).padding(11).background(SumbarDesign.subtle, in: RoundedRectangle(cornerRadius: 10))
                .onChange(of: search) { _, _ in if !filtered.contains(where: { $0.id == store.selectedInstrumentID }) { selectFirst() } }
            if !filtered.isEmpty {
                Picker("Бумага", selection: $store.selectedInstrumentID) {
                    Text("Выберите бумагу").tag(Optional<String>.none)
                    ForEach(filtered) { i in Text("\(i.ticker) · \(i.name)").tag(Optional(i.id)) }
                }.labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
                    .onChange(of: store.selectedInstrumentID) { _, _ in
                        entry = ""; target = ""
                        if let i = store.instrument, !isDesignPreview { Task { await store.loadDetail(i) } }
                    }
                if let i = store.instrument, i.kind == securityKind { securityContent(i) }
            } else { empty("Ничего не найдено", detail: store.cache.instruments.isEmpty ? "Котировки появятся после первой проверки." : "Попробуйте другой тикер или название.", icon: "magnifyingglass") }
            sourceLink("UZSE через Finmind", url: "https://finmind.uz/developers")
        }
    }
    private func selectFirst() { store.selectedInstrumentID = filtered.first?.id }
    @ViewBuilder private func securityContent(_ i: Instrument) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(Money.format(i.price)).font(.system(size: 38, weight: .medium, design: .rounded)).tracking(-1).monospacedDigit()
                Text(i.currency + " / шт.").font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                if let change = i.changePercent { DeltaBadge(value: change) }
                else { Text("Изменение: —").font(.system(size: 11)).foregroundStyle(.secondary) }
            }
            Text("Сессия \(i.tradeDate ?? "без сделок") · к предыдущей сохранённой сессии")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("Цена закрытия").font(.system(size: 12, weight: .semibold))
                Spacer()
                ForEach([30, 90, 365], id: \.self) { days in
                    periodButton(days == 30 ? "1М" : days == 90 ? "3М" : "1Г", selected: stockPeriod == days) { stockPeriod = days }
                }
            }
            let cutoff = Dates.calendar.date(byAdding: .day, value: -stockPeriod, to: Date())!
            let history = store.cache.details[i.id]?.history.filter { $0.date >= cutoff } ?? []
            PriceChart(points: history, intraday: false, color: SumbarDesign.blue, unit: i.currency)
            if store.loadingChart { ProgressView("Загрузка истории…").controlSize(.small) }
            if let error = store.chartError { notice(error) }
            Text("Цены закрытия торговых сессий. Внутридневная лента не подключена.").font(.system(size: 11)).foregroundStyle(.secondary)
            securityCalculator(i)
        }
    }
    private func securityCalculator(_ i: Instrument) -> some View {
        Surface {
            VStack(alignment: .leading, spacing: 14) {
                Label("Сценарий сделки", systemImage: "function").font(.system(size: 12, weight: .semibold))
                HStack(spacing: 14) { field("Количество, шт.", text: $quantity); field("Комиссия за сторону, %", text: $fee) }
                HStack(spacing: 14) {
                    field("Цена покупки", text: $entry, prompt: Money.format(i.price))
                    field("Цена продажи", text: $target, prompt: Money.format(i.price))
                }
                Divider()
                if let p = i.price, let count = valid(quantity), count == Decimal(NSDecimalNumber(decimal: count).int64Value), let buy = entry.isEmpty ? p : valid(entry), buy > 0, let sell = target.isEmpty ? p : valid(target), let f = valid(fee), f <= 100 {
                    let calc = Money.investment(quantity: count, entry: buy, exit: sell, fee: f)
                    resultRow("Покупка с комиссией", value: Money.format(calc.cost) + " " + i.currency)
                    resultRow("Продажа после комиссии", value: Money.format(calc.proceeds) + " " + i.currency)
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Результат сделки").font(.system(size: 11)).foregroundStyle(.secondary)
                            Text(Money.format(calc.profit) + " " + i.currency).font(.system(size: 23, weight: .medium, design: .rounded)).monospacedDigit()
                        }
                        Spacer()
                        if calc.cost > 0 { DeltaBadge(value: calc.profit / calc.cost * 100) }
                    }.padding(.top, 3)
                } else { notice("Укажите целое количество, цену покупки больше нуля и комиссию от 0 до 100%. Для расчёта нужна котировка.") }
                if let detail = store.cache.details[i.id], let face = detail.faceValue, let coupon = detail.coupon {
                    resultRow("Годовой купон на бумагу", value: Money.format(face * coupon / 100) + " " + i.currency)
                    Text("Номинал × ставка купона, не доходность к погашению.").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Text("Без налогов, дивидендов и купонов. Последняя цена не гарантирует цену новой сделки.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private var settings: some View {
        VStack(alignment: .leading, spacing: 18) {
            Surface {
                VStack(alignment: .leading, spacing: 15) {
                    Label("Внешний вид", systemImage: "circle.lefthalf.filled").font(.system(size: 13, weight: .semibold))
                    Picker("Оформление", selection: $appearance) {
                        Text("Как в macOS").tag("system"); Text("Светлое").tag("light"); Text("Тёмное").tag("dark")
                    }.pickerStyle(.segmented).labelsHidden()
                    Text("Материалы и контраст адаптируются к оформлению Mac и настройкам доступности.").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Surface {
                VStack(alignment: .leading, spacing: 15) {
                    Label("Обновление данных", systemImage: "arrow.clockwise").font(.system(size: 13, weight: .semibold))
                    Picker("Проверять каждые", selection: $store.refreshMinutes) { Text("15 минут").tag(15); Text("30 минут").tag(30); Text("Час").tag(60) }
                    Text("Проверяем источники даже при закрытой панели. Во сне и после выхода проверок нет; после пробуждения обновляем данные.").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Label("Данные остаются на вашем Mac", systemImage: "lock.shield").font(.system(size: 13, weight: .medium))
            Text("Курсы и настройки сохраняются локально. Без аккаунта и аналитики. Для загрузки приложение обращается к ЦБ и Finmind.").font(.system(size: 12)).foregroundStyle(.secondary)
            DisclosureGroup("Об источниках и условиях") {
                Text("Finmind предназначен для личного использования. Для распространения котировок требуется разрешение поставщика; лицензия кода не распространяется на данные.").font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 8)
                Link("Условия Finmind", destination: URL(string: "https://finmind.uz/developers")!).font(.system(size: 11)).padding(.top, 5)
            }.font(.system(size: 12))
            if let error = store.storageError { notice(error) }
            HStack { Text("Sumbar \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")"); Spacer(); Text("Открытый исходный код") }.font(.system(size: 11)).foregroundStyle(.secondary)
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
            Button("Проверить источники") { Task { await store.refresh() } }.buttonStyle(.bordered).disabled(store.loading)
        }.frame(maxWidth: .infinity).padding(.vertical, 65)
    }
}

struct PriceChart: View {
    let points: [PricePoint]
    let intraday: Bool
    let color: Color
    var unit = "UZS"
    @State private var selected: Date?
    private var nearest: PricePoint? {
        guard let selected else { return nil }
        return points.min { abs($0.date.timeIntervalSince(selected)) < abs($1.date.timeIntervalSince(selected)) }
    }
    private var axisFormat: Date.FormatStyle {
        var format: Date.FormatStyle = intraday ? .dateTime.hour().minute() : .dateTime.day(.twoDigits).month(.twoDigits)
        format.locale = Locale(identifier: "ru_RU")
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
                    Text("Здесь появится динамика").font(.system(size: 12, weight: .medium))
                    Text(intraday ? "Ждём первое наблюдение за сегодня" : "Источник пока не вернул историю").font(.system(size: 11)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).frame(height: 155)
            } else {
                Chart {
                    ForEach(points) { point in
                        AreaMark(x: .value("Время", point.date), yStart: .value("Основание", domain.lowerBound), yEnd: .value("Цена", point.value))
                            .foregroundStyle(LinearGradient(colors: [color.opacity(0.20), color.opacity(0.015)], startPoint: .top, endPoint: .bottom)).interpolationMethod(.stepEnd)
                        LineMark(x: .value("Время", point.date), y: .value("Цена", point.value))
                            .foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 2.1, lineCap: .round, lineJoin: .round)).interpolationMethod(.stepEnd)
                        if points.count == 1 || point.id == points.last?.id {
                            PointMark(x: .value("Время", point.date), y: .value("Цена", point.value)).foregroundStyle(color).symbolSize(25)
                        }
                    }
                    if let point = nearest {
                        RuleMark(x: .value("Время", point.date)).foregroundStyle(Color.secondary.opacity(0.4)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        PointMark(x: .value("Время", point.date), y: .value("Цена", point.value)).foregroundStyle(color).symbolSize(40)
                    }
                }.chartYScale(domain: domain).chartXSelection(value: $selected)
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                            AxisValueLabel(format: axisFormat).font(.system(size: 11))
                        }
                    }.chartYAxis {
                        AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 4])).foregroundStyle(SumbarDesign.separator)
                            AxisValueLabel().font(.system(size: 11))
                        }
                    }.frame(height: 140)
                    .accessibilityLabel("График цены в \(unit), \(points.count) наблюдений, время Ташкента")
                HStack {
                    if let point = nearest { Text("\(Dates.display(point.date))  ·  \(Money.format(point.price)) \(unit)") }
                    else if points.count == 1 { Text("Одно наблюдение. Новые появятся после проверок.") }
                    else { Text("\(points.count) наблюдений"); Spacer(); Text(unit) }
                }.font(.system(size: 11)).foregroundStyle(.secondary).frame(height: 14)
            }
        }.environment(\.timeZone, TimeZone(identifier: "Asia/Tashkent")!)
    }
}
