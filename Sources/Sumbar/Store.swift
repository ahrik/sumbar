import SwiftUI

struct MarketLoaders: Sendable {
    var currencies: @Sendable (Date) async throws -> [CurrencyQuote] = { try await Providers.currencies(date: $0) }
    var instruments: @Sendable () async throws -> [Instrument] = { try await Providers.instruments() }
    var detail: @Sendable (Instrument) async throws -> SecurityDetail = { try await Providers.detail($0) }
    var bank: @Sendable (BankProviders.Source) async throws -> [BankQuote] = { try await BankProviders.load($0) }
}

@MainActor @Observable final class MarketStore {
    var cache = CacheState()
    var fxError: String?; var stocksError: String?
    var currencyHistoryError: String?
    var securityHistoryErrors: [String: String] = [:]
    var bankErrors: [String: String] = [:]
    var loadingBanks = false
    var loading = false
    var now = Date()
    var preferences: OverviewPreferences { didSet { if let defaults { preferences.save(defaults) } } }
    var refreshMinutes: Int {
        get { preferences.refreshMinutes }
        set { preferences.refreshMinutes = newValue }
    }
    var selectedCurrency: String {
        get { preferences.selectedCurrency }
        set { preferences.selectedCurrency = newValue }
    }
    var selectedInstrumentID: String? {
        get { preferences.selectedInstrumentID }
        set { preferences.selectedInstrumentID = newValue }
    }
    var panelTab = 0
    var detailLoading: Set<String> = []
    var historyLoading = false
    var loadingChart: Bool { historyLoading || !detailLoading.isEmpty }
    private var timerTask: Task<Void, Never>?
    private var attempted: [String: Date] = [:]
    private var fileURL: URL?
    private let defaults: UserDefaults?
    private let loaders: MarketLoaders
    var storageError: String?

    init(inMemory: Bool = false, defaults: UserDefaults? = nil, loaders: MarketLoaders = MarketLoaders()) {
        self.loaders = loaders
        self.defaults = inMemory ? defaults : (defaults ?? .standard)
        preferences = self.defaults.map(OverviewPreferences.load) ?? OverviewPreferences()
        if inMemory { return }
        do {
            let dir = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("Sumbar")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent("cache.json"); fileURL = url
            if FileManager.default.fileExists(atPath: url.path) { cache = try JSONDecoder().decode(CacheState.self, from: Data(contentsOf: url)) }
        } catch { storageError = "Не удалось прочитать сохранённые данные: \(error.localizedDescription)" }
    }
    var currency: CurrencyQuote? { cache.currencies.first { $0.code == selectedCurrency } }
    var instrument: Instrument? { cache.instruments.first { $0.id == selectedInstrumentID } }
    var favoriteInstruments: [Instrument] { preferences.favoriteInstruments.compactMap { id in cache.instruments.first { $0.id == id } } }
    var bankChoices: [BankQuote] {
        Dictionary(grouping: cache.bankQuotes ?? [], by: \.bankID).values.compactMap(\.first).sorted { $0.bankName < $1.bankName }
    }
    func toggleCurrencyFavorite(_ code: String) { toggle(code, in: &preferences.favoriteCurrencies) }
    func toggleBankFavorite(_ id: String) { toggle(id, in: &preferences.favoriteBanks) }
    func toggleInstrumentFavorite(_ id: String) { toggle(id, in: &preferences.favoriteInstruments) }
    private func toggle(_ id: String, in values: inout [String]) {
        if values.contains(id) { values.removeAll { $0 == id } } else { values.append(id) }
    }
    func pinCurrency() { preferences.menuCurrency = selectedCurrency; preferences.menuMode = .cbu }
    func pinBank(_ id: String) {
        preferences.menuBankID = id; preferences.menuCurrency = selectedCurrency; preferences.menuMode = .bank
        preferences.menuBankChannel = preferences.bankChannel; preferences.menuBankAction = preferences.bankAction
    }
    func pinInstrument(_ id: String) { preferences.menuInstrumentID = id; preferences.menuMode = .security }
    func openPinnedQuote() {
        switch preferences.menuMode {
        case .icon: break
        case .cbu: selectedCurrency = preferences.menuCurrency; panelTab = 0
        case .bank:
            selectedCurrency = preferences.menuCurrency; panelTab = 1
            preferences.bankChannel = preferences.menuBankChannel; preferences.bankAction = preferences.menuBankAction
        case .security: selectedInstrumentID = preferences.menuInstrumentID; panelTab = 2
        }
    }
    func status(for tab: Int, at date: Date? = nil) -> DataStatus {
        let checked = tab == 1 ? cache.bankQuotes?.map(\.observedAt).max() : tab == 2 ? cache.stocksChecked : cache.fxChecked
        let error = tab == 1 ? (bankErrors.isEmpty ? nil : "Не все источники обновлены") : tab == 2 ? stocksError : fxError
        return DataStatus(checkedAt: checked, error: error, now: date ?? now, maximumAge: Double(refreshMinutes * 120))
    }
    func menuBarQuote(at date: Date? = nil) -> MenuBarQuote {
        let date = date ?? now
        let p = preferences
        switch p.menuMode {
        case .icon: return MenuBarQuote(title: "", tooltip: "Sumbar — финансы Узбекистана")
        case .cbu:
            let quote = cache.currencies.first { $0.code == p.menuCurrency }
            let status = status(for: 0, at: date)
            let effective = quote.flatMap { Dates.parse($0.effectiveDate, pattern: "dd.MM.yyyy") }
            let usable = status.isCurrent && effective.map { $0 <= date.addingTimeInterval(300) && date.timeIntervalSince($0) < 8 * 86400 } == true
            return MenuBarQuote(title: "\(p.menuCurrency) ЦБ \(usable ? Money.format(quote?.price) : "—")", tooltip: "Курс ЦБ за 1 \(p.menuCurrency), UZS\nДействует с \(quote?.effectiveDate ?? "—")\n\(status.text)\n\(usable ? "" : "Нет действующей публикации или свежей проверки\n")Ташкент")
        case .bank:
            let row = BankComparison.rows(quotes: cache.bankQuotes ?? [], currency: p.menuCurrency, channel: p.menuBankChannel, action: p.menuBankAction, amount: nil, failedProviders: Set(bankErrors.keys), at: date).first { $0.quote.bankID == p.menuBankID }
            let operation = p.menuBankAction == .buy ? "купить" : "продать"
            let channel = p.menuBankChannel == .cash ? "касса" : p.menuBankChannel == .app ? "прил." : "ATM"
            let name = row?.quote.bankName ?? "Выберите банк в настройках"
            let timing = row.map { "Проверено \(Dates.display($0.quote.observedAt))\n" + ($0.quote.publishedAt.map { "Публикация \(Dates.display($0))" } ?? "Время публикации не указано") } ?? "Котировка недоступна"
            return MenuBarQuote(title: "\(p.menuCurrency) \(channel) \(operation) \(row?.eligible == true ? Money.format(row?.rate) : "—")", tooltip: "\(name) · \(p.menuBankChannel.title)\nВы \(p.menuBankAction == .buy ? "покупаете" : "продаёте") \(p.menuCurrency), UZS за единицу\n\(row?.quote.sourceName ?? "")\n\(timing)\n\(row?.eligible == true ? "Без комиссий; уточните условия в банке" : "Нет свежей котировки для этой операции")\nТашкент")
        case .security:
            let instrument = cache.instruments.first { $0.id == p.menuInstrumentID }
            let status = status(for: 2, at: date)
            let session = instrument?.tradeDate.flatMap { Dates.parse($0) }
            let usable = status.isCurrent && session.map { $0 <= date.addingTimeInterval(300) } == true
            return MenuBarQuote(title: "\(instrument?.ticker ?? "Бумага") закр. \(usable ? Money.format(instrument?.price) : "—")", tooltip: "\(instrument?.name ?? "Выберите бумагу в настройках")\nПоследняя сохранённая цена закрытия, \(instrument?.currency ?? "UZS")\nСессия \(instrument?.tradeDate ?? "—")\n\(status.text)\nUZSE через Finmind · дневные данные")
        }
    }
    func start() {
        guard timerTask == nil else { return }
        timerTask = Task { [weak self] in
            await self?.refresh(force: false)
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                guard let self else { return }
                self.now = Date()
                await self.refresh(force: false)
            }
        }
    }
    func stop() { timerTask?.cancel(); timerTask = nil }
    private func shouldFetch(_ key: String, force: Bool, checked: Date? = nil) -> Bool {
        let previous = attempted[key] ?? checked
        guard force || previous == nil || Date().timeIntervalSince(previous!) >= Double(refreshMinutes * 60) else { return false }
        attempted[key] = Date()
        return true
    }
    func refresh(force: Bool = true) async {
        now = Date()
        guard !loading else { return }; loading = true; defer { loading = false; save() }
        async let fx: Void = refreshFX(force: force)
        async let securities: Void = refreshStocks(force: force)
        async let banks: Void = refreshBanks(force: force)
        _ = await (fx, securities, banks)
    }
    func refreshBanks(force: Bool = true) async {
        guard !loadingBanks else { return }; loadingBanks = true
        defer { loadingBanks = false; save() }
        // Explicit retained tasks avoid the optimized TaskGroup startup crash in 0.1.0.
        let sources = BankProviders.sources.filter { source in
            shouldFetch(source.id, force: force, checked: cache.bankQuotes?.filter { $0.provider == source.id }.map(\.observedAt).max())
        }
        let jobs = sources.map { source in
            Task { @MainActor in
                do {
                    let quotes = try await loaders.bank(source)
                    var current = cache.bankQuotes ?? []
                    current.removeAll { $0.provider == source.id }
                    current.append(contentsOf: quotes); cache.bankQuotes = current
                    bankErrors.removeValue(forKey: source.id)
                } catch { bankErrors[source.id] = error.localizedDescription }
            }
        }
        await withTaskCancellationHandler {
            for job in jobs { await job.value }
        } onCancel: {
            for job in jobs { job.cancel() }
        }
    }
    private func refreshFX(force: Bool) async {
        guard shouldFetch("fx", force: force, checked: cache.fxChecked) else { return }
        do {
            let quotes = try await loaders.currencies(Date()); cache.currencies = quotes; cache.fxChecked = Date(); fxError = nil
            let now = Date(); let start = Dates.calendar.date(byAdding: .day, value: -7, to: now)!
            for q in quotes {
                var points = cache.observed[q.code, default: []].filter { $0.date >= start }
                if now.timeIntervalSince(points.last?.date ?? .distantPast) >= 60 { points.append(PricePoint(date: now, price: q.price)) }
                cache.observed[q.code] = points
            }
        } catch { fxError = "Курсы не обновлены: \(error.localizedDescription)" }
    }
    private func refreshStocks(force: Bool) async {
        guard shouldFetch("stocks", force: force, checked: cache.stocksChecked) else { return }
        do {
            cache.instruments = try await loaders.instruments(); cache.stocksChecked = Date(); stocksError = nil
            if selectedInstrumentID == nil { selectedInstrumentID = cache.instruments.first { $0.ticker == "AGBA" }?.id ?? cache.instruments.first?.id }
            if let instrument { await loadDetail(instrument, force: true) }
        } catch { stocksError = "Котировки не обновлены: \(error.localizedDescription)" }
    }
    func loadDetail(_ instrument: Instrument, force: Bool = false) async {
        guard !detailLoading.contains(instrument.id), force || cache.details[instrument.id] == nil else { return }
        detailLoading.insert(instrument.id)
        defer { detailLoading.remove(instrument.id); save() }
        do { cache.details[instrument.id] = try await loaders.detail(instrument); securityHistoryErrors.removeValue(forKey: instrument.id) }
        catch { securityHistoryErrors[instrument.id] = "История \(instrument.ticker) недоступна: \(error.localizedDescription)" }
    }
    func loadCurrencyHistory(force: Bool = false) async {
        guard !historyLoading, force || cache.currencyHistoryDay != Dates.day(), shouldFetch("fxHistory", force: force) else { return }
        historyLoading = true
        defer { historyLoading = false; save() }
        var history: [String: [PricePoint]] = [:]
        do {
            for offset in (0...6).reversed() {
                try Task.checkCancellation()
                let date = Dates.calendar.date(byAdding: .day, value: -offset, to: Date())!
                let quotes = try await loaders.currencies(date)
                for q in quotes {
                    guard let effective = Dates.parse(q.effectiveDate, pattern: "dd.MM.yyyy") else { continue }
                    if history[q.code, default: []].last?.date != effective { history[q.code, default: []].append(PricePoint(date: effective, price: q.price)) }
                }
            }
            cache.currencyHistory = history.mapValues { $0.sorted { $0.date < $1.date } }; cache.currencyHistoryDay = Dates.day(); currencyHistoryError = nil
        } catch { currencyHistoryError = "Архив ЦБ недоступен: \(error.localizedDescription)" }
    }
    private func save() {
        guard let fileURL else { return }
        do { try JSONEncoder().encode(cache).write(to: fileURL, options: .atomic) }
        catch { storageError = "Данные не сохранены: \(error.localizedDescription)" }
    }
}
