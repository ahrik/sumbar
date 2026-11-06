import XCTest
@testable import Sumbar

private actor ArchiveProbe {
    var dates: [Date] = []
    var failOnCall: Int?
    var holdFirst = false
    var continuation: CheckedContinuation<Void, Never>?
    func configure(failOnCall: Int? = nil, holdFirst: Bool = false) { self.failOnCall = failOnCall; self.holdFirst = holdFirst }
    func release() { continuation?.resume(); continuation = nil }
    func load(_ date: Date) async throws -> [CurrencyQuote] {
        dates.append(date)
        if holdFirst, dates.count == 1 { await withCheckedContinuation { continuation = $0 } }
        if dates.count == failOnCall { throw MarketError.http(503) }
        return [CurrencyQuote(code: "USD", name: "Synthetic", price: 100, change: 0, effectiveDate: Dates.formatter("dd.MM.yyyy").string(from: date)), CurrencyQuote(code: "EUR", name: "Synthetic", price: 120, change: 0, effectiveDate: Dates.formatter("dd.MM.yyyy").string(from: date))]
    }
}
final class HistoryAndContextTests: XCTestCase {
    func testRangePlansAreBoundedAnchoredAndUseCalendarMonths() {
        let end = Dates.parse("2026-11-06")!
        XCTAssertEqual(FXPeriod.week.requestedDates(ending: end).count, 7)
        XCTAssertLessThanOrEqual(FXPeriod.month.requestedDates(ending: end).count, 32)
        XCTAssertLessThanOrEqual(FXPeriod.quarter.requestedDates(ending: end).count, 16)
        let year = FXPeriod.year.requestedDates(ending: end)
        XCTAssertLessThanOrEqual(year.count, 55)
        XCTAssertEqual(year, year.sorted()); XCTAssertEqual(Set(year).count, year.count)
        XCTAssertTrue(year.dropFirst().dropLast().allSatisfy { Dates.calendar.component(.weekday, from: $0) == 2 })
        let next = FXPeriod.year.requestedDates(ending: end.addingTimeInterval(86400))
        XCTAssertGreaterThan(Set(year).intersection(next).count, 50)
        let leapMonth = FXPeriod.month.requestedDates(ending: Dates.parse("2024-03-31")!)
        XCTAssertEqual(leapMonth.first.map(Dates.day), "2024-02-29")
    }
    func testWeekendSnapshotKeepsEffectiveDateAndDecimalConversion() throws {
        let saturday = Dates.parse("2026-10-31")!
        let quote = CurrencyQuote(code: "JPY", name: "Synthetic", price: Decimal(string: "80.005")!, change: 0, effectiveDate: "30.10.2026")
        let snapshot = try FXSnapshot.validated(quotes: [quote], requested: saturday, checkedAt: saturday)
        XCTAssertEqual(snapshot.requestedDay, "2026-10-31"); XCTAssertEqual(snapshot.quote("JPY")?.effectiveDate, "30.10.2026")
        XCTAssertEqual(snapshot.converted(amount: 2, code: "JPY", inverse: false), Decimal(string: "160.01"))
        let restored = try JSONDecoder().decode(FXSnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(restored.quote("JPY")?.price, quote.price)
        XCTAssertEqual(snapshot.converted(amount: Decimal(string: "160.01"), code: "JPY", inverse: true), 2)
        XCTAssertNil(snapshot.converted(amount: 10, code: "USD", inverse: false))
        XCTAssertNil(snapshot.converted(amount: -1, code: "JPY", inverse: false))
        let future = CurrencyQuote(code: "USD", name: "Synthetic", price: 1, change: 0, effectiveDate: "01.11.2026")
        XCTAssertThrowsError(try FXSnapshot.validated(quotes: [future], requested: saturday, checkedAt: saturday))
        XCTAssertThrowsError(try FXSnapshot.validated(quotes: [quote, quote], requested: saturday, checkedAt: saturday))
    }
    @MainActor func testSnapshotsAreSharedAcrossCurrenciesAndSurviveRestart() async throws {
        let directory = TestPaths.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let probe = ArchiveProbe(); let file = directory.appendingPathComponent("archive.json")
        let archive = CurrencyArchive(fileURL: file, loader: { try await probe.load($0) })
        let date = Dates.parse("2026-10-30")!
        async let first = archive.fetch(date)
        async let second = archive.fetch(date)
        _ = try await (first, second)
        let count = await probe.dates.count; XCTAssertEqual(count, 1)
        XCTAssertNotNil(archive.snapshot(on: date)?.quote("EUR"))
        let restored = CurrencyArchive(fileURL: file, loader: { _ in XCTFail("Cached history should not fetch again"); return [] })
        let snapshot = try await restored.fetch(date)
        XCTAssertEqual(snapshot.quote("USD")?.price, 100)
        XCTAssertEqual(snapshot.requestedDay, "2026-10-30")
    }
    @MainActor func testFutureRequestsAreRejectedWithoutNetworkAndTashkentDateIsUsed() async throws {
        let probe = ArchiveProbe(); let archive = CurrencyArchive(loader: { try await probe.load($0) })
        let now = ISO8601DateFormatter().date(from: "2026-11-05T20:30:00Z")!
        let snapshot = try await archive.fetch(now, now: now)
        XCTAssertEqual(snapshot.requestedDay, "2026-11-06")
        do { _ = try await archive.fetch(now.addingTimeInterval(86400), now: now); XCTFail("Future date accepted") } catch {}
        let count = await probe.dates.count; XCTAssertEqual(count, 1)
    }
    @MainActor func testCurrentRefreshSeedsTodayWithoutAnExtraRequest() async throws {
        let archive = CurrencyArchive(loader: { _ in XCTFail("Current quote should be reused"); return [] })
        let now = Date()
        let quote = CurrencyQuote(code: "USD", name: "Synthetic", price: 100, change: 0, effectiveDate: Dates.formatter("dd.MM.yyyy").string(from: now))
        archive.rememberCurrent([quote], checkedAt: now)
        let snapshot = try await archive.fetch(now, now: now)
        XCTAssertEqual(snapshot.quote("USD")?.price, 100)
        XCTAssertEqual(snapshot.checkedAt, now)
    }
    @MainActor func testPartialFailureRetainsSuccessfulPointsAndStopsRequestLoop() async {
        let probe = ArchiveProbe(); await probe.configure(failOnCall: 4)
        let archive = CurrencyArchive(loader: { try await probe.load($0) })
        let end = Dates.parse("2026-11-06")!
        await archive.loadRange(currency: "USD", period: .year, ending: end)
        let series = archive.series(currency: "USD", period: .year, ending: end)
        XCTAssertEqual(series.loadedCount, 3); XCTAssertEqual(series.points.count, 3)
        XCTAssertFalse(series.isComplete); XCTAssertTrue(series.sampled); XCTAssertNotNil(archive.rangeError)
        let count = await probe.dates.count; XCTAssertEqual(count, 4)
    }
    @MainActor func testCancellationFinishesCurrentSharedFetchButStartsNoMoreDates() async {
        let probe = ArchiveProbe(); await probe.configure(holdFirst: true)
        let archive = CurrencyArchive(loader: { try await probe.load($0) })
        let task = Task { await archive.loadRange(currency: "USD", period: .year) }
        while await probe.dates.isEmpty { await Task.yield() }
        task.cancel(); await probe.release(); await task.value
        let count = await probe.dates.count
        XCTAssertEqual(count, 1); XCTAssertFalse(archive.loadingRange)
    }
    func testDetailDecoderKeepsZeroVolumeAndUnknownCouponFrequency() throws {
        let data = Data(#"{"history":[{"date":"2026-11-05","close":"101"}],"quote":{"trade_date":"2026-11-05","open":"99","high":"102","low":"0","volume":"0","turnover":null},"face_value":"100000","coupon_rate_pct":"25","coupon_frequency_per_year":null,"issue_date":"2025-01-01","maturity_date":"2028-01-01","price_basis":"percent_of_par","issuer":{"name":"Synthetic issuer","sector":"Synthetic sector"},"volume_unit":"bonds","disclosures":[{"title":"Synthetic fact","published_date":"2026-11-01","url":"https://new.openinfo.uz/ru/facts/1"},{"title":"Unsafe link","url":"javascript:alert(1)"},{"title":"Untrusted link","url":"https://openinfo.uz.example.test/1"}]}"#.utf8)
        let detail = try Providers.decodeDetail(data)
        XCTAssertEqual(detail.session?.volume, 0); XCTAssertNil(detail.session?.low); XCTAssertNil(detail.session?.turnover)
        XCTAssertNil(detail.couponFrequency); XCTAssertEqual(detail.maturityDate, "2028-01-01")
        XCTAssertEqual(detail.issuerName, "Synthetic issuer"); XCTAssertEqual(detail.disclosures?.count, 1)
        XCTAssertEqual(detail.unitPrice(101, kind: "bond"), 101000)
        XCTAssertNil(SecurityDetail(history: [], coupon: nil, faceValue: 100000).unitPrice(101, kind: "bond"))
        let legacy = Data(#"{"history":[],"coupon":null,"faceValue":null}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(SecurityDetail.self, from: legacy).session)
    }
    func testLiveSecurityContextWhenRequested() async throws {
        guard ProcessInfo.processInfo.environment["SUMBAR_LIVE_TESTS"] == "1" else { throw XCTSkip("Live sources are opt-in") }
        let i = Instrument(key: "AGBA", ticker: "AGBA", name: "Live source", kind: "stock", currency: "UZS", price: nil, changePercent: nil, tradeDate: nil)
        let detail = try await Providers.detail(i)
        XCTAssertNotNil(detail.session); XCTAssertFalse(detail.history.isEmpty)
        XCTAssertTrue((detail.disclosures ?? []).allSatisfy { $0.url.scheme == "https" })
    }
}
