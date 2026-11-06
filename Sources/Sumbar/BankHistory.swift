import Foundation
import Observation

struct BankObservation: Codable, Identifiable, Sendable {
    let observedAt: Date
    let publishedAt: Date?
    let buy: Decimal?
    let sell: Decimal?
    var id: Date { observedAt }
}
struct BankHistorySeries: Codable, Identifiable, Sendable {
    var quote: BankQuote
    var observations: [BankObservation]
    var id: String { quote.id }
}

/// Local successful observations, never an inferred bank publication archive.
@MainActor @Observable final class BankHistory {
    private(set) var series: [String: BankHistorySeries] = [:]
    var storageError: String? {
        let tr = L10n(language: language)
        if readFailed { return tr("Не удалось прочитать историю банков. Исходный файл сохранён.") }
        return writeFailure.map { tr("Не удалось сохранить историю банков: \(tr.error($0))") }
    }
    var language = AppLanguage.ru
    private let fileURL: URL?
    private var readFailed = false
    private var writeFailure: Error?
    private var dirty = false
    init(fileURL: URL? = nil) {
        self.fileURL = fileURL
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do { series = try JSONDecoder().decode([String: BankHistorySeries].self, from: Data(contentsOf: fileURL)) }
        catch { readFailed = true }
    }
    func record(_ quotes: [BankQuote], provider: String, at now: Date = Date()) {
        prune(at: now)
        for quote in quotes where quote.provider == provider && quote.isCurrent(at: now) && quote.observedAt <= now {
            let buy = quote.buy.flatMap { $0 > 0 ? $0 : nil }
            let sell = quote.sell.flatMap { $0 > 0 ? $0 : nil }
            guard buy != nil || sell != nil else { continue }
            var value = series[quote.id] ?? BankHistorySeries(quote: quote, observations: [])
            // Manual refreshes cannot duplicate or reorder a successful observation.
            if let last = value.observations.last, quote.observedAt.timeIntervalSince(last.observedAt) < 60 { continue }
            value.quote = quote
            value.observations.append(BankObservation(observedAt: quote.observedAt, publishedAt: quote.publishedAt, buy: buy, sell: sell))
            series[quote.id] = value; dirty = true
        }
    }
    func observations(for id: String, days: Int, ending now: Date) -> [BankObservation] {
        let start = now.addingTimeInterval(-Double(days) * 86400)
        return (series[id]?.observations ?? []).filter { $0.observedAt >= start && $0.observedAt <= now }
    }
    func save() {
        guard dirty, let fileURL, !readFailed else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(series).write(to: fileURL, options: .atomic)
            dirty = false; writeFailure = nil
        } catch { writeFailure = error }
    }
    private func prune(at now: Date) {
        let cutoff = now.addingTimeInterval(-31 * 86400)
        for key in Array(series.keys) {
            let oldCount = series[key]!.observations.count
            series[key]!.observations.removeAll { $0.observedAt < cutoff }
            if series[key]!.observations.isEmpty { series.removeValue(forKey: key); dirty = true }
            else if series[key]!.observations.count != oldCount { dirty = true }
        }
    }
}
