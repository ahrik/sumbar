import Foundation
import Observation

enum FXPeriod: String, CaseIterable, Identifiable {
    case today, week, month, quarter, year
    var id: String { rawValue }
    var isSampled: Bool { self == .quarter || self == .year }
    func requestedDates(ending date: Date) -> [Date] {
        let calendar = Dates.calendar
        let end = calendar.startOfDay(for: date)
        let start: Date
        switch self {
        case .today: return [end]
        case .week: start = calendar.date(byAdding: .day, value: -6, to: end)!
        case .month: start = calendar.date(byAdding: .month, value: -1, to: end)!
        case .quarter: start = calendar.date(byAdding: .month, value: -3, to: end)!
        case .year: start = calendar.date(byAdding: .year, value: -1, to: end)!
        }
        var dates: [Date] = [start]
        var cursor = calendar.date(byAdding: .day, value: 1, to: start)!
        while cursor < end {
            // Fixed Mondays allow almost all past samples to be reused on the next day.
            if !isSampled || calendar.component(.weekday, from: cursor) == 2 { dates.append(cursor) }
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor)!
        }
        if start != end { dates.append(end) }
        return dates
    }
}
struct FXSnapshot: Codable, Equatable, Sendable {
    let requestedDay: String
    let checkedAt: Date
    let quotes: [CurrencyQuote]
    func quote(_ code: String) -> CurrencyQuote? { quotes.first { $0.code == code } }
    func converted(amount: Decimal?, code: String, inverse: Bool) -> Decimal? {
        guard let amount, amount >= 0, amount <= 1_000_000_000_000, let quote = quote(code), quote.price > 0 else { return nil }
        return inverse ? amount / quote.price : amount * quote.price
    }
    static func validated(quotes: [CurrencyQuote], requested: Date, checkedAt: Date) throws -> Self {
        let day = Dates.calendar.startOfDay(for: requested)
        let usable = quotes.filter {
            guard $0.price > 0, let effective = Dates.parse($0.effectiveDate, pattern: "dd.MM.yyyy") else { return false }
            return effective <= day
        }
        guard !usable.isEmpty, Set(usable.map(\.code)).count == usable.count else { throw MarketError.invalidData }
        return Self(requestedDay: Dates.day(day), checkedAt: checkedAt, quotes: usable)
    }
}
struct FXArchiveSeries {
    let points: [PricePoint]
    let requestedCount: Int
    let loadedCount: Int
    let currencyCount: Int
    let sampled: Bool
    var isComplete: Bool { loadedCount == requestedCount }
}

@MainActor @Observable final class CurrencyArchive {
    private(set) var snapshots: [String: FXSnapshot] = [:]
    private(set) var loadingDays: Set<String> = []
    private(set) var loadingRange = false
    private(set) var rangeError: String?
    private(set) var storageError: String?
    private(set) var dateErrors: [String: String] = [:]
    var language = AppLanguage.ru
    private var tr: L10n { L10n(language: language) }
    private let fileURL: URL?
    private let loader: @Sendable (Date) async throws -> [CurrencyQuote]
    private var inFlight: [String: Task<FXSnapshot, Error>] = [:]
    private var attempts: [String: Date] = [:]
    private var rangeTask: Task<Void, Never>?
    private var rangeID: UUID?
    private var readFailed = false

    init(fileURL: URL? = nil, loader: @escaping @Sendable (Date) async throws -> [CurrencyQuote] = { try await Providers.currencies(date: $0) }) {
        self.fileURL = fileURL; self.loader = loader
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do { snapshots = try JSONDecoder().decode([String: FXSnapshot].self, from: Data(contentsOf: fileURL)) }
        catch { readFailed = true; storageError = tr("Не удалось прочитать архив. Исходный файл сохранён: \(tr.error(error))") }
    }
    func snapshot(on date: Date) -> FXSnapshot? { snapshots[Dates.day(date)] }
    func rememberCurrent(_ quotes: [CurrencyQuote], checkedAt: Date) {
        guard let snapshot = try? FXSnapshot.validated(quotes: quotes, requested: checkedAt, checkedAt: checkedAt) else { return }
        snapshots[snapshot.requestedDay] = snapshot
        dateErrors.removeValue(forKey: snapshot.requestedDay)
        save()
    }
    func series(currency: String, period: FXPeriod, ending date: Date) -> FXArchiveSeries {
        let dates = period.requestedDates(ending: date)
        let values = dates.compactMap { snapshots[Dates.day($0)] }
        var points: [Date: Decimal] = [:]
        var currencyCount = 0
        for value in values {
            if let quote = value.quote(currency), let effective = Dates.parse(quote.effectiveDate, pattern: "dd.MM.yyyy") {
                // Repeated weekend requests describe the same official publication.
                points[effective] = quote.price; currencyCount += 1
            }
        }
        return FXArchiveSeries(points: points.map { PricePoint(date: $0.key, price: $0.value) }.sorted { $0.date < $1.date }, requestedCount: dates.count, loadedCount: values.count, currencyCount: currencyCount, sampled: period.isSampled)
    }
    @discardableResult func fetch(_ requested: Date, force: Bool = false, now fixedNow: Date? = nil) async throws -> FXSnapshot {
        let now = fixedNow ?? Date()
        let date = Dates.calendar.startOfDay(for: requested)
        let key = Dates.day(date)
        guard date <= Dates.calendar.startOfDay(for: now) else { throw MarketError.invalidData }
        if let task = inFlight[key] { return try await task.value }
        if let saved = snapshots[key], !force, key != Dates.day(now) || now.timeIntervalSince(saved.checkedAt) < 15 * 60 { return saved }
        if let attempt = attempts[key], now.timeIntervalSince(attempt) < 60 {
            if let saved = snapshots[key] { return saved }
            throw RequestError.backoff(attempt.addingTimeInterval(60))
        }
        attempts[key] = now; loadingDays.insert(key)
        let loader = self.loader
        let task = Task {
            let quotes = try await loader(date)
            return try FXSnapshot.validated(quotes: quotes, requested: date, checkedAt: fixedNow ?? Date())
        }
        inFlight[key] = task
        defer { inFlight.removeValue(forKey: key); loadingDays.remove(key) }
        do {
            let snapshot = try await task.value
            snapshots[key] = snapshot; dateErrors.removeValue(forKey: key)
            save()
            return snapshot
        } catch {
            dateErrors[key] = tr.error(error)
            throw error
        }
    }
    func loadRange(currency: String, period: FXPeriod, ending date: Date = Date()) async {
        guard period != .today else { return }
        let previous = rangeTask
        previous?.cancel()
        let id = UUID(); rangeID = id; loadingRange = true; rangeError = nil
        let task = Task { [weak self] in
            // At most one range request is in flight even after rapid range changes.
            await previous?.value
            guard let self else { return }
            defer { if self.rangeID == id { self.loadingRange = false } }
            for date in period.requestedDates(ending: date) {
                guard !Task.isCancelled else { return }
                do { _ = try await self.fetch(date) }
                catch {
                    if !Task.isCancelled, self.rangeID == id { self.rangeError = self.tr("Архив загружен не полностью: \(self.tr.error(error))") }
                    return
                }
            }
        }
        rangeTask = task
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    }
    func cancelRange() { rangeTask?.cancel(); rangeID = nil; loadingRange = false }
    #if DEBUG
    func seedPreview(_ values: [FXSnapshot]) { snapshots = Dictionary(uniqueKeysWithValues: values.map { ($0.requestedDay, $0) }) }
    #endif
    private func save() {
        guard let fileURL, !readFailed else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(snapshots).write(to: fileURL, options: .atomic)
            storageError = nil
        } catch { storageError = tr("Не удалось сохранить архив: \(tr.error(error))") }
    }
}
