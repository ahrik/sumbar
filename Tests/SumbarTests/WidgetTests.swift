import XCTest
@testable import Sumbar

private actor WidgetLoadCounter {
    var count = 0
    func load(_ date: Date) async throws -> [CurrencyQuote] {
        count += 1
        try await Task.sleep(for: .milliseconds(30))
        return [widgetQuote(date)]
    }
}

private func widgetQuote(_ date: Date) -> CurrencyQuote {
    CurrencyQuote(code: "USD", name: "Dollar", price: 12000.25, change: -1.5,
                  effectiveDate: Dates.formatter("dd.MM.yyyy").string(from: date))
}

final class WidgetTests: XCTestCase {
    func testPublicationAndCheckExpireIndependentlyAndTimelineHasBothBoundaries() throws {
        let now = try XCTUnwrap(Dates.parse("2026-11-06")).addingTimeInterval(3600)
        let snapshot = WidgetRateSnapshot(quotes: [widgetQuote(now)], checkedAt: now)
        XCTAssertTrue(snapshot.isFresh(at: now))
        XCTAssertFalse(snapshot.isFresh(at: now.addingTimeInterval(3601)))
        XCTAssertFalse(snapshot.isFresh(at: now.addingTimeInterval(-301)))
        XCTAssertEqual(snapshot.quote("USD", at: now)?.price, Decimal(string: "12000.25"))
        XCTAssertNil(snapshot.quote("EUR", at: now))
        let stale = try XCTUnwrap(snapshot.nextChange(after: now))
        XCTAssertEqual(stale, now.addingTimeInterval(3601))
        let expired = try XCTUnwrap(snapshot.nextChange(after: stale))
        XCTAssertNil(snapshot.quote("USD", at: expired))
        XCTAssertNil(snapshot.nextChange(after: expired))
        let future = WidgetRateSnapshot(quotes: [widgetQuote(now.addingTimeInterval(86400))], checkedAt: now)
        XCTAssertNil(future.quote("USD", at: now))
        // Friday's official publication remains usable over the weekend, with its original date.
        XCTAssertNotNil(snapshot.quote("USD", at: now.addingTimeInterval(2 * 86400)))
    }

    func testCacheRoundTripFailureDoesNotChangePriceOrCheckDate() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("widget.json")
        let now = Date()
        let store = WidgetRateStore(fileURL: file) { [widgetQuote($0)] }
        let online = await store.refresh(at: now)
        XCTAssertFalse(online.failed)
        let bytes = try Data(contentsOf: file)
        let offline = WidgetRateStore(fileURL: file) { _ in throw URLError(.notConnectedToInternet) }
        let saved = await offline.refresh(at: now.addingTimeInterval(3601))
        XCTAssertTrue(saved.failed)
        XCTAssertEqual(saved.snapshot?.checkedAt, online.snapshot?.checkedAt)
        XCTAssertEqual(saved.snapshot?.quotes, online.snapshot?.quotes)
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }

    func testMultipleWidgetInstancesShareOneRequestAndReuseRecentCache() async throws {
        let counter = WidgetLoadCounter()
        let store = WidgetRateStore(fileURL: nil) { try await counter.load($0) }
        let now = Date()
        async let first = store.refresh(at: now)
        async let second = store.refresh(at: now)
        let results = await [first, second]
        XCTAssertTrue(results.allSatisfy { !$0.failed && $0.snapshot?.quotes.count == 1 })
        _ = await store.refresh(at: now.addingTimeInterval(899))
        let initialCount = await counter.count
        XCTAssertEqual(initialCount, 1)
        _ = await store.refresh(at: now.addingTimeInterval(900))
        let laterCount = await counter.count
        XCTAssertEqual(laterCount, 2)
    }

    func testCorruptCacheIsPreservedAndEmptyResponseNeverBecomesAQuote() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let original = Data("unreadable cache".utf8)
        try original.write(to: file)
        let store = WidgetRateStore(fileURL: file) { [widgetQuote($0)] }
        let result = await store.refresh()
        XCTAssertNotNil(result.snapshot)
        XCTAssertEqual(try Data(contentsOf: file), original)
        let empty = WidgetRateStore(fileURL: nil) { _ in [] }
        let missing = await empty.refresh()
        XCTAssertTrue(missing.failed)
        XCTAssertNil(missing.snapshot)
    }

    func testWriteFailureStillReturnsOnlineDataAndFutureCheckDoesNotSuppressFetch() async throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: parent) }
        try Data("a file, not a directory".utf8).write(to: parent)
        let counter = WidgetLoadCounter()
        let store = WidgetRateStore(fileURL: parent.appendingPathComponent("cache.json")) { try await counter.load($0) }
        let now = Date()
        let initial = await store.refresh(at: now.addingTimeInterval(86400))
        XCTAssertFalse(initial.failed)
        XCTAssertNotNil(initial.snapshot)
        let recovered = await store.refresh(at: now)
        XCTAssertEqual(recovered.snapshot?.checkedAt, now)
        let count = await counter.count
        XCTAssertEqual(count, 2)
    }

    func testDeepLinkRoundTripAndRejectionOfUnrelatedOrMalformedURLs() throws {
        XCTAssertEqual(WidgetLink.currency(from: WidgetLink.url(currency: "EUR")), "EUR")
        for link in ["https://currency?code=USD", "sumbar://bank?code=USD", "sumbar://currency/path?code=USD",
                     "sumbar://currency?code=usd", "sumbar://currency?code=US", "sumbar://currency", "sumbar://currency?code=USD%0A"] {
            XCTAssertNil(WidgetLink.currency(from: try XCTUnwrap(URL(string: link))), link)
        }
    }
}
