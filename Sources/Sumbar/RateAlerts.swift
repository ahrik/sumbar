import Foundation
import Observation

enum AlertSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case cbu, bank
    var id: String { rawValue }
    var title: String { self == .cbu ? "Курс ЦБ" : "Курс банка" }
}
enum AlertComparison: String, Codable, CaseIterable, Identifiable, Sendable {
    case atOrAbove, atOrBelow
    var id: String { rawValue }
    var title: String { self == .atOrAbove ? "Не ниже" : "Не выше" }
    func matches(_ value: Decimal, threshold: Decimal) -> Bool { self == .atOrAbove ? value >= threshold : value <= threshold }
}
enum AlertRuleState: String, Codable, Sendable { case active, paused, triggered }
enum AlertDeliveryState: String, Codable, Sendable { case pending, sent, failed, expired }

struct AlertObservation: Codable, Equatable, Sendable {
    let value: Decimal
    let checkedAt: Date
    let publication: String
    let sourceName: String
    let sourceURL: String
    let validUntil: Date

    static func lookup(_ rule: RateAlertRule, cache: CacheState, fxError: String?, bankErrors: Set<String>, refreshMinutes: Int, now: Date) -> Self? {
        if rule.source == .cbu {
            guard DataStatus(checkedAt: cache.fxChecked, error: fxError, now: now, maximumAge: Double(refreshMinutes * 120)).isCurrent,
                  let checked = cache.fxChecked, let quote = cache.currencies.first(where: { $0.code == rule.currency }), quote.price > 0,
                  let effective = Dates.parse(quote.effectiveDate, pattern: "dd.MM.yyyy"), effective <= now.addingTimeInterval(300), now.timeIntervalSince(effective) < 8 * 86400 else { return nil }
            return Self(value: quote.price, checkedAt: checked, publication: quote.effectiveDate, sourceName: "ЦБ Узбекистана", sourceURL: "https://cbu.uz/ru/arkhiv-kursov-valyut/", validUntil: min(checked.addingTimeInterval(Double(refreshMinutes * 120)), effective.addingTimeInterval(8 * 86400)))
        }
        // Unknown publication times may appear in comparison, but cannot trigger an alert.
        let rows = BankComparison.rows(quotes: cache.bankQuotes ?? [], currency: rule.currency, channel: rule.channel, action: rule.action, amount: nil, failedProviders: bankErrors, at: now)
        guard let row = rows.first(where: { $0.quote.bankID == rule.bankID }), row.eligible,
              let publication = row.quote.publishedAt, let rate = row.rate else { return nil }
        return Self(value: rate, checkedAt: row.quote.observedAt, publication: Dates.display(publication), sourceName: row.quote.bankName, sourceURL: row.quote.sourceURL, validUntil: min(row.quote.observedAt.addingTimeInterval(2 * 3600), publication.addingTimeInterval(48 * 3600)))
    }
}
struct RateAlertEvent: Codable, Equatable, Sendable {
    let ruleID: UUID
    let observation: AlertObservation
    let createdAt: Date
    var notificationID: String { "sumbar.rate." + ruleID.uuidString }
}
struct RateAlertRule: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    let source: AlertSource
    let currency: String
    let bankID: String?
    let bankName: String?
    let channel: BankChannel
    let action: ExchangeAction
    let comparison: AlertComparison
    let threshold: Decimal
    let notifyOnFirstMatch: Bool
    var state = AlertRuleState.active
    var lastCondition: Bool?
    var event: RateAlertEvent?
    var delivery: AlertDeliveryState?

    /// Consume only an eligible observation. Missing data never rearms or fires a rule.
    mutating func evaluate(_ observation: AlertObservation?) -> Bool {
        guard state == .active, threshold > 0, threshold <= 1_000_000_000_000, let observation else { return false }
        let matches = comparison.matches(observation.value, threshold: threshold)
        let fire = matches && (lastCondition == false || (lastCondition == nil && notifyOnFirstMatch))
        lastCondition = matches
        return fire
    }
}
struct RateAlertDraft {
    var source = AlertSource.cbu
    var currency = "USD"
    var bankID: String?
    var channel = BankChannel.cash
    var action = ExchangeAction.buy
    var comparison = AlertComparison.atOrBelow
    var threshold = ""
    var notifyOnFirstMatch = false
    func rule(bankName: String? = nil) -> RateAlertRule? {
        guard let value = Money.parse(threshold), value > 0, value <= 1_000_000_000_000, source == .cbu || bankID != nil else { return nil }
        return RateAlertRule(source: source, currency: currency, bankID: bankID, bankName: bankName, channel: channel, action: action, comparison: comparison, threshold: value, notifyOnFirstMatch: notifyOnFirstMatch)
    }
}

@MainActor @Observable final class RateAlerts {
    private(set) var rules: [RateAlertRule] = []
    var language = AppLanguage.ru
    private var tr: L10n { L10n(language: language) }
    var draft = RateAlertDraft()
    var error: String?
    var canDeliver = false
    var sender: (@MainActor (RateAlertEvent, RateAlertRule) async throws -> Void)?
    var onRemove: ((String) -> Void)?
    private let fileURL: URL?
    private var evaluating = false
    private var sending: Set<UUID> = []
    private var storageReadable = true

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do { rules = try JSONDecoder().decode([RateAlertRule].self, from: Data(contentsOf: fileURL)) }
        catch { storageReadable = false; self.error = tr("Не удалось прочитать правила уведомлений. Файл сохранён: \(tr.error(error))") }
    }
    private func commit(_ updated: [RateAlertRule]) -> Bool {
        guard storageReadable else { return false }
        do {
            if let fileURL {
                try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try JSONEncoder().encode(updated).write(to: fileURL, options: .atomic)
            }
            rules = updated; error = nil
            return true
        } catch { self.error = tr("Не удалось сохранить правила: \(tr.error(error))"); return false }
    }
    @discardableResult func add(_ rule: RateAlertRule) -> Bool { commit(rules + [rule]) }
    func remove(_ id: UUID) {
        guard let rule = rules.first(where: { $0.id == id }) else { return }
        if commit(rules.filter { $0.id != id }), let event = rule.event { onRemove?(event.notificationID) }
    }
    func setPaused(_ id: UUID, paused: Bool) {
        var updated = rules
        guard let index = updated.firstIndex(where: { $0.id == id }), updated[index].state != .triggered else { return }
        updated[index].state = paused ? .paused : .active
        // Resuming waits for a new crossing; it cannot generate a surprise current-state alert.
        updated[index].lastCondition = nil
        if !paused { updated[index].lastCondition = true }
        _ = commit(updated)
    }
    func evaluate(cache: CacheState, fxError: String?, bankErrors: Set<String>, refreshMinutes: Int, now: Date) async {
        guard !evaluating, canDeliver, sender != nil else { return }
        evaluating = true; defer { evaluating = false }
        var updated = rules
        for index in updated.indices where updated[index].state == .active {
            let observation = AlertObservation.lookup(updated[index], cache: cache, fxError: fxError, bankErrors: bankErrors, refreshMinutes: refreshMinutes, now: now)
            if updated[index].evaluate(observation), let observation {
                updated[index].state = .triggered
                updated[index].event = RateAlertEvent(ruleID: updated[index].id, observation: observation, createdAt: now)
                updated[index].delivery = .pending
            }
        }
        // Persist consumed conditions before handing a stable event ID to macOS.
        guard updated == rules || commit(updated) else { return }
        for id in rules.filter({ $0.state == .triggered && $0.delivery == .pending }).map(\.id) { await deliver(id) }
    }
    func deliver(_ id: UUID) async {
        guard !sending.contains(id), canDeliver, let sender, let rule = rules.first(where: { $0.id == id }), let event = rule.event, rule.delivery != .sent else { return }
        if event.observation.validUntil < Date() {
            var updated = rules
            if let index = updated.firstIndex(where: { $0.id == id }) { updated[index].delivery = .expired; _ = commit(updated) }
            return
        }
        sending.insert(id); defer { sending.remove(id) }
        do {
            try await sender(event, rule)
            var updated = rules
            if let index = updated.firstIndex(where: { $0.id == id }) { updated[index].delivery = .sent; _ = commit(updated) }
            else { onRemove?(event.notificationID) }
        } catch {
            var updated = rules
            if let index = updated.firstIndex(where: { $0.id == id }) { updated[index].delivery = .failed; _ = commit(updated) }
            self.error = tr("Не удалось отправить уведомление: \(tr.error(error))")
        }
    }
}
