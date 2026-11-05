import SwiftUI

@MainActor @Observable final class MarketStore {
    var cache = CacheState()
    var fxError: String?; var stocksError: String?; var chartError: String?
    var bankErrors: [String: String] = [:]
    var loadingBanks = false
    var loading = false; var loadingChart = false
    var refreshMinutes: Int { didSet { UserDefaults.standard.set(refreshMinutes, forKey: "refreshMinutes") } }
    var selectedCurrency: String { didSet { UserDefaults.standard.set(selectedCurrency, forKey: "currency") } }
    var selectedInstrumentID: String?
    private var detailLoading: Set<String> = []
    private var historyLoading = false
    private var timerTask: Task<Void, Never>?
    private var lastAttempt: Date?
    private var fileURL: URL?
    var storageError: String?
    init(inMemory: Bool = false) {
        if inMemory { refreshMinutes = 15; selectedCurrency = "USD"; return }
        let minutes = UserDefaults.standard.object(forKey: "refreshMinutes") as? Int ?? 15
        refreshMinutes = [15,30,60].contains(minutes) ? minutes : 15
        selectedCurrency = UserDefaults.standard.string(forKey: "currency") ?? "USD"
        do {
            let dir = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("Sumbar")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent("cache.json"); fileURL = url
            if FileManager.default.fileExists(atPath: url.path) { cache = try JSONDecoder().decode(CacheState.self, from: Data(contentsOf: url)) }
        } catch { storageError = "Не удалось прочитать сохранённые данные: \(error.localizedDescription)" }
    }
    var currency: CurrencyQuote? { cache.currencies.first { $0.code == selectedCurrency } }
    var instrument: Instrument? { cache.instruments.first { $0.id == selectedInstrumentID } }
    func start() {
        guard timerTask == nil else { return }
        timerTask = Task { [weak self] in
            await self?.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard let self else { return }
                if Date().timeIntervalSince(self.lastAttempt ?? .distantPast) >= Double(self.refreshMinutes * 60) { await self.refresh() }
            }
        }
    }
    func refresh() async {
        guard !loading else { return }; loading = true; lastAttempt = Date(); defer { loading = false; save() }
        async let fx: Void = refreshFX()
        async let securities: Void = refreshStocks()
        async let banks: Void = refreshBanks()
        _ = await (fx, securities, banks)
    }
    func refreshBanks() async {
        guard !loadingBanks else { return }; loadingBanks = true
        defer { loadingBanks = false; save() }
        // Retain explicit jobs through completion. The previous nested task group
        // crashed in TaskGroup::offer in the shipped optimized macOS binary.
        // Requests still run concurrently; no group-owned result context escapes.
        let jobs = BankProviders.sources.map { source in
            Task { @MainActor in
                do {
                    let quotes = try await BankProviders.load(source)
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

    private func refreshFX() async {
        do {
            let quotes = try await Providers.currencies(); cache.currencies = quotes; cache.fxChecked = Date(); fxError = nil
            let now = Date(); let start = Dates.calendar.date(byAdding: .day, value: -7, to: now)!
            for q in quotes {
                var points = cache.observed[q.code, default: []].filter { $0.date >= start }
                if now.timeIntervalSince(points.last?.date ?? .distantPast) >= 60 { points.append(PricePoint(date: now, price: q.price)) }
                cache.observed[q.code] = points
            }
        } catch { fxError = "Курсы не обновлены: \(error.localizedDescription)" }
    }
    private func refreshStocks() async {
        do {
            cache.instruments = try await Providers.instruments(); cache.stocksChecked = Date(); stocksError = nil
            if selectedInstrumentID == nil { selectedInstrumentID = cache.instruments.first { $0.ticker == "AGBA" }?.id ?? cache.instruments.first?.id }
            if let instrument { await loadDetail(instrument, force: true) }
        } catch { stocksError = "Котировки не обновлены: \(error.localizedDescription)" }
    }
    func loadDetail(_ instrument: Instrument, force: Bool = false) async {
        guard !detailLoading.contains(instrument.id), force || cache.details[instrument.id] == nil else { return }
        detailLoading.insert(instrument.id); loadingChart = true
        defer { detailLoading.remove(instrument.id); loadingChart = !detailLoading.isEmpty; save() }
        do { cache.details[instrument.id] = try await Providers.detail(instrument); chartError = nil }
        catch { chartError = "История \(instrument.ticker) недоступна: \(error.localizedDescription)" }
    }
    func loadCurrencyHistory() async {
        guard !historyLoading, cache.currencyHistoryDay != Dates.day() else { return }
        historyLoading = true; loadingChart = true
        defer { historyLoading = false; loadingChart = !detailLoading.isEmpty; save() }
        // Seven daily requests populate every currency, rather than one request per chart.
        var history: [String: [PricePoint]] = [:]
        do {
            for offset in (0...6).reversed() {
                let date = Dates.calendar.date(byAdding: .day, value: -offset, to: Date())!
                let quotes = try await Providers.currencies(date: date)
                for q in quotes {
                    guard let effective = Dates.parse(q.effectiveDate, pattern: "dd.MM.yyyy") else { continue }
                    if history[q.code, default: []].last?.date != effective { history[q.code, default: []].append(PricePoint(date: effective, price: q.price)) }
                }
            }
            cache.currencyHistory = history.mapValues { $0.sorted { $0.date < $1.date } }; cache.currencyHistoryDay = Dates.day(); chartError = nil
        } catch { chartError = "Архив ЦБ недоступен: \(error.localizedDescription)" }
    }
    private func save() {
        guard let fileURL else { return }
        do { try JSONEncoder().encode(cache).write(to: fileURL, options: .atomic) }
        catch { storageError = "Данные не сохранены: \(error.localizedDescription)" }
    }
}
