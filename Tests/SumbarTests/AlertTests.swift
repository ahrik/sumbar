import XCTest
@testable import Sumbar

final class AlertTests: XCTestCase {
    private func cache(_ price: Decimal, at now: Date) -> CacheState {
        var cache = CacheState()
        cache.fxChecked = now
        cache.currencies = [CurrencyQuote(code: "USD", name: "Synthetic", price: price, change: 0, effectiveDate: Dates.formatter("dd.MM.yyyy").string(from: now))]
        return cache
    }
    private func rule(immediate: Bool = false, source: AlertSource = .cbu, action: ExchangeAction = .buy) -> RateAlertRule {
        RateAlertRule(source: source, currency: "USD", bankID: source == .bank ? "test" : nil, bankName: "Synthetic", channel: .app, action: action, comparison: .atOrBelow, threshold: 100, notifyOnFirstMatch: immediate)
    }
    @MainActor private func evaluate(_ alerts: RateAlerts, _ cache: CacheState, now: Date, errors: Set<String> = []) async {
        await alerts.evaluate(cache: cache, fxError: nil, bankErrors: errors, refreshMinutes: 15, now: now)
    }
    @MainActor func testOneShotCrossingSurvivesRestartAndDoesNotRepeat() async throws {
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("temp/tests/\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("alerts.json")
        let now = Date()
        let alerts = RateAlerts(fileURL: url)
        var sent: [String] = []
        alerts.canDeliver = true; alerts.sender = { event, _ in sent.append(event.notificationID) }
        XCTAssertTrue(alerts.add(rule()))
        await evaluate(alerts, cache(105, at: now), now: now)
        XCTAssertTrue(sent.isEmpty)
        await evaluate(alerts, cache(100, at: now), now: now)
        await evaluate(alerts, cache(99, at: now), now: now)
        XCTAssertEqual(sent.count, 1); XCTAssertEqual(alerts.rules[0].state, .triggered)
        let restored = RateAlerts(fileURL: url)
        restored.canDeliver = true; restored.sender = { event, _ in sent.append(event.notificationID) }
        await evaluate(restored, cache(90, at: now), now: now)
        XCTAssertEqual(sent.count, 1); XCTAssertEqual(restored.rules[0].delivery, .sent)
    }
    @MainActor func testAlreadyMetWaitsForNewCrossingUnlessImmediateWasChosen() async {
        let now = Date()
        let alerts = RateAlerts()
        var count = 0
        alerts.canDeliver = true; alerts.sender = { _, _ in count += 1 }
        _ = alerts.add(rule()); _ = alerts.add(rule(immediate: true))
        await evaluate(alerts, cache(99, at: now), now: now)
        XCTAssertEqual(count, 1)
        await evaluate(alerts, cache(99, at: now), now: now)
        XCTAssertEqual(count, 1)
        await evaluate(alerts, cache(101, at: now), now: now)
        await evaluate(alerts, cache(100, at: now), now: now)
        XCTAssertEqual(count, 2)
    }
    @MainActor func testMissingFailedAndStaleBankDataNeverTriggerAndSidesRemainSeparate() async {
        let now = Date()
        var state = CacheState()
        func quote(publication: Date?, channel: BankChannel = .app) -> BankQuote {
            BankQuote(bankID: "test", bankName: "Synthetic", currency: "USD", channel: channel, buy: 90, sell: 110, provider: "ipak", sourceURL: "https://example.test", publishedAt: publication, observedAt: now)
        }
        let buy = rule(immediate: true, source: .bank)
        state.bankQuotes = [quote(publication: nil)]
        XCTAssertNil(AlertObservation.lookup(buy, cache: state, fxError: nil, bankErrors: [], refreshMinutes: 15, now: now))
        state.bankQuotes = [quote(publication: now.addingTimeInterval(-49 * 3600))]
        XCTAssertNil(AlertObservation.lookup(buy, cache: state, fxError: nil, bankErrors: [], refreshMinutes: 15, now: now))
        state.bankQuotes = [quote(publication: now, channel: .cash)]
        XCTAssertNil(AlertObservation.lookup(buy, cache: state, fxError: nil, bankErrors: [], refreshMinutes: 15, now: now))
        state.bankQuotes = [quote(publication: now)]
        XCTAssertNil(AlertObservation.lookup(buy, cache: state, fxError: nil, bankErrors: ["ipak"], refreshMinutes: 15, now: now))
        XCTAssertEqual(AlertObservation.lookup(buy, cache: state, fxError: nil, bankErrors: [], refreshMinutes: 15, now: now)?.value, 110)
        let sell = rule(immediate: true, source: .bank, action: .sell)
        XCTAssertEqual(AlertObservation.lookup(sell, cache: state, fxError: nil, bankErrors: [], refreshMinutes: 15, now: now)?.value, 90)
    }
    @MainActor func testDeniedDeliveryPauseAndResumeDoNotConsumeOrSendSurpriseAlert() async {
        let now = Date(); let alerts = RateAlerts(); let rule = rule(immediate: true)
        var count = 0
        alerts.sender = { _, _ in count += 1 }; _ = alerts.add(rule)
        await evaluate(alerts, cache(99, at: now), now: now)
        XCTAssertEqual(alerts.rules[0].state, .active); XCTAssertNil(alerts.rules[0].lastCondition)
        alerts.canDeliver = true; alerts.setPaused(rule.id, paused: true)
        await evaluate(alerts, cache(99, at: now), now: now)
        alerts.setPaused(rule.id, paused: false)
        await evaluate(alerts, cache(99, at: now), now: now)
        XCTAssertEqual(count, 0)
        await evaluate(alerts, cache(101, at: now), now: now)
        await evaluate(alerts, cache(99, at: now), now: now)
        XCTAssertEqual(count, 1)
    }
    @MainActor func testDeliveryFailureRequiresExplicitRetryAndKeepsStableIdentifier() async {
        let now = Date(); let alerts = RateAlerts(); let rule = rule(immediate: true)
        var ids: [String] = []
        alerts.canDeliver = true; alerts.sender = { event, _ in ids.append(event.notificationID); throw NotificationError.notAuthorized }
        _ = alerts.add(rule)
        await evaluate(alerts, cache(99, at: now), now: now)
        await evaluate(alerts, cache(99, at: now), now: now)
        XCTAssertEqual(ids.count, 1); XCTAssertEqual(alerts.rules[0].delivery, .failed)
        alerts.sender = { event, _ in ids.append(event.notificationID) }
        await alerts.deliver(rule.id)
        XCTAssertEqual(ids.count, 2); XCTAssertEqual(ids[0], ids[1]); XCTAssertEqual(alerts.rules[0].delivery, .sent)
    }
    @MainActor func testCorruptStorageIsPreservedAndCannotBeOverwritten() throws {
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("temp/tests/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("alerts.json"); let bytes = Data("broken synthetic data".utf8)
        try bytes.write(to: url)
        let alerts = RateAlerts(fileURL: url)
        XCTAssertNotNil(alerts.error); XCTAssertFalse(alerts.add(rule())); XCTAssertEqual(try Data(contentsOf: url), bytes)
    }
    @MainActor func testFailedPersistenceDoesNotConsumeConditionOrSend() async throws {
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("temp/tests/\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("alerts.json")
        let alerts = RateAlerts(fileURL: url); let now = Date()
        XCTAssertTrue(alerts.add(rule(immediate: true)))
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        var count = 0; alerts.canDeliver = true; alerts.sender = { _, _ in count += 1 }
        await evaluate(alerts, cache(99, at: now), now: now)
        XCTAssertEqual(count, 0); XCTAssertEqual(alerts.rules[0].state, .active); XCTAssertNil(alerts.rules[0].lastCondition)
        XCTAssertNotNil(alerts.error)
    }
    @MainActor func testPendingPersistedEventIsRecoveredWithSameIdentifier() async throws {
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("temp/tests/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(); var saved = rule(immediate: true)
        let observation = try XCTUnwrap(AlertObservation.lookup(saved, cache: cache(99, at: now), fxError: nil, bankErrors: [], refreshMinutes: 15, now: now))
        saved.state = .triggered; saved.delivery = .pending
        saved.event = RateAlertEvent(ruleID: saved.id, observation: observation, createdAt: now)
        let url = directory.appendingPathComponent("alerts.json")
        try JSONEncoder().encode([saved]).write(to: url)
        let alerts = RateAlerts(fileURL: url); var ids: [String] = []
        alerts.canDeliver = true; alerts.sender = { event, _ in ids.append(event.notificationID) }
        await evaluate(alerts, cache(110, at: now), now: now)
        await evaluate(alerts, cache(110, at: now), now: now)
        XCTAssertEqual(ids, [saved.event!.notificationID]); XCTAssertEqual(alerts.rules[0].delivery, .sent)
    }
    @MainActor func testExpiredPendingObservationIsNotSentAfterRestart() async throws {
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("temp/tests/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let old = Date().addingTimeInterval(-3 * 3600); var saved = rule(immediate: true)
        let observation = try XCTUnwrap(AlertObservation.lookup(saved, cache: cache(99, at: old), fxError: nil, bankErrors: [], refreshMinutes: 15, now: old))
        saved.state = .triggered; saved.delivery = .pending
        saved.event = RateAlertEvent(ruleID: saved.id, observation: observation, createdAt: old)
        let url = directory.appendingPathComponent("alerts.json"); try JSONEncoder().encode([saved]).write(to: url)
        let alerts = RateAlerts(fileURL: url); var count = 0
        alerts.canDeliver = true; alerts.sender = { _, _ in count += 1 }
        await evaluate(alerts, cache(110, at: Date()), now: Date())
        XCTAssertEqual(count, 0); XCTAssertEqual(alerts.rules[0].delivery, .expired)
    }
    @MainActor func testOpeningRuleRestoresItsOperationAndDoesNotChangePin() {
        let store = MarketStore(inMemory: true); let rule = rule(source: .bank, action: .sell)
        _ = store.alerts.add(rule); store.preferences.menuMode = .cbu; store.openAlert(rule.id)
        XCTAssertEqual(store.panelTab, 1); XCTAssertEqual(store.focusedBankID, "test")
        XCTAssertEqual(store.preferences.bankAction, .sell); XCTAssertEqual(store.preferences.bankChannel, .app)
        XCTAssertEqual(store.preferences.menuMode, .cbu)
    }
}
