import XCTest
@testable import Sumbar

private actor HistoryBankLoader {
    var failing = false
    func fail() { failing = true }
    func load(_ source: BankProviders.Source) throws -> [BankQuote] {
        guard source.id == "ipak", !failing else { throw MarketError.invalidData }
        return [BankQuote(bankID: "test", bankName: "Synthetic", currency: "USD", channel: .cash, buy: 100, sell: 110, provider: source.id, sourceURL: source.url, publishedAt: nil, observedAt: Date())]
    }
}

final class BankHistoryTests: XCTestCase {
    private func quote(_ date: Date, provider: String = "ipak", channel: BankChannel = .cash, currency: String = "USD", buy: Decimal? = 12000, sell: Decimal? = 12100, published: Date? = nil) -> BankQuote {
        BankQuote(bankID: "test", bankName: "Synthetic bank", currency: currency, channel: channel, buy: buy, sell: sell, provider: provider, sourceURL: "https://example.test", publishedAt: published, observedAt: date)
    }
    @MainActor func testDecimalPersistenceSourceChannelAndCurrencyIsolation() throws {
        let directory = TestPaths.directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("history.json"); let history = BankHistory(fileURL: file)
        let now = Date()
        let original = quote(now, buy: Decimal(string: "12345.6789"), published: now.addingTimeInterval(-3600))
        history.record([original, quote(now, channel: .app), quote(now, currency: "EUR")], provider: "ipak", at: now)
        history.record([quote(now, provider: "bankuz")], provider: "bankuz", at: now)
        history.save()
        let restored = BankHistory(fileURL: file)
        XCTAssertEqual(restored.series.count, 4)
        let values = restored.observations(for: original.id, days: 7, ending: now)
        XCTAssertEqual(values.count, 1); XCTAssertEqual(values.first?.buy, original.buy)
        XCTAssertEqual(values.first?.publishedAt?.timeIntervalSince1970 ?? 0, original.publishedAt!.timeIntervalSince1970, accuracy: 0.001)
    }
    @MainActor func testRepeatedChecksKeepFlatPricesButNeverFillGapsOrDuplicateRefreshes() {
        let history = BankHistory(); let now = Date()
        history.record([quote(now)], provider: "ipak", at: now)
        history.record([quote(now), quote(now.addingTimeInterval(30))], provider: "ipak", at: now.addingTimeInterval(30))
        let later = now.addingTimeInterval(3 * 86400)
        history.record([quote(later)], provider: "ipak", at: later)
        let points = history.observations(for: quote(now).id, days: 7, ending: later)
        XCTAssertEqual(points.map(\.observedAt), [now, later]); XCTAssertEqual(points.first?.buy, points.last?.buy)
    }
    @MainActor func testInvalidFutureStaleAndWrongProviderSamplesAreExcluded() {
        let history = BankHistory(); let now = Date()
        history.record([quote(now, provider: "bankuz"), quote(now.addingTimeInterval(10)), quote(now.addingTimeInterval(-3 * 3600)), quote(now, buy: 0, sell: -1), quote(now, published: now.addingTimeInterval(-49 * 3600))], provider: "ipak", at: now)
        XCTAssertTrue(history.series.isEmpty)
        history.record([quote(now, buy: nil)], provider: "ipak", at: now)
        let points = history.observations(for: quote(now).id, days: 7, ending: now)
        XCTAssertNil(points.first?.buy); XCTAssertEqual(points.first?.sell, 12100); XCTAssertNil(points.first?.publishedAt)
    }
    @MainActor func testRetentionAndSelectedWindowDoNotInventEarlierData() {
        let history = BankHistory(); let now = Date()
        for age in [32, 30, 8, 1, 0] {
            let date = now.addingTimeInterval(-Double(age) * 86400)
            history.record([quote(date)], provider: "ipak", at: date)
        }
        XCTAssertEqual(history.series[quote(now).id]?.observations.count, 4)
        XCTAssertEqual(history.observations(for: quote(now).id, days: 7, ending: now).count, 2)
        XCTAssertEqual(history.observations(for: quote(now).id, days: 31, ending: now).count, 4)
        XCTAssertEqual(history.observations(for: quote(now).id, days: 7, ending: now.addingTimeInterval(-2 * 86400)).count, 1)
    }
    @MainActor func testCorruptFileIsPreservedAndFailedWritesAreVisible() throws {
        let directory = TestPaths.directory(); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("history.json"); let broken = Data("broken".utf8)
        try broken.write(to: file)
        let history = BankHistory(fileURL: file); let now = Date()
        history.record([quote(now)], provider: "ipak", at: now); history.save()
        XCTAssertNotNil(history.storageError); XCTAssertEqual(try Data(contentsOf: file), broken)
        history.language = .uz
        XCTAssertTrue(history.storageError?.contains("Bank tarixini") == true)
        let unwritable = BankHistory(fileURL: file.appendingPathComponent("child.json"))
        unwritable.record([quote(now)], provider: "ipak", at: now); unwritable.save()
        XCTAssertNotNil(unwritable.storageError)
        try FileManager.default.removeItem(at: file)
        unwritable.save()
        XCTAssertNil(unwritable.storageError)
        XCTAssertEqual(BankHistory(fileURL: file.appendingPathComponent("child.json")).series.count, 1)
    }
    @MainActor func testStoreRecordsOnlySuccessfulProvidersAndRetainsHistoryAfterFailure() async {
        var loaders = MarketLoaders()
        let loader = HistoryBankLoader()
        loaders.bank = { try await loader.load($0) }
        let store = MarketStore(inMemory: true, loaders: loaders)
        await store.refreshBanks()
        XCTAssertEqual(store.bankHistory.series.count, 1)
        let id = store.bankHistory.series.keys.first!
        XCTAssertEqual(store.bankHistory.observations(for: id, days: 7, ending: store.now).count, 1)
        XCTAssertEqual(store.bankErrors.count, BankProviders.sources.count - 1)
        await store.refreshBanks()
        XCTAssertEqual(store.bankHistory.series.values.first?.observations.count, 1)
        await loader.fail()
        await store.refreshBanks()
        XCTAssertEqual(store.bankErrors.count, BankProviders.sources.count)
        XCTAssertEqual(store.bankHistory.series.values.first?.observations.count, 1)
    }
}
