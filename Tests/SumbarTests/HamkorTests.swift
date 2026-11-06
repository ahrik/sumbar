import XCTest
@testable import Sumbar

final class HamkorTests: XCTestCase {
    private let now = Dates.parse("2026-11-06T12:00:00", pattern: "yyyy-MM-dd'T'HH:mm:ss")!
    private func row(code: String = "USD", destination: String = "2", tier: Int = 0, buy: Any = 1234500, sell: Any = 1245600, created: String = "2026-11-06T10:01:13.354633+05:00", effective: String = "2026-11-06T10:00:00+05:00") -> [String: Any] {
        ["currency_char":code, "destination_code":destination, "begin_sum_i":tier, "buying_rate":buy, "selling_rate":sell, "created_at":created, "begin_date":effective]
    }
    private func decode(_ rows: [[String: Any]], status: String = "Success", error: Int = 0) throws -> [BankQuote] {
        let data = try JSONSerialization.data(withJSONObject: ["status":status, "error_code":error, "data":rows])
        return try BankProviders.decode(String(decoding: data, as: UTF8.self), provider: "hamkor", at: now)
    }
    func testSidesMinorUnitsAndIndependentChannelsHaveOwnTimes() throws {
        let values = try decode([row(), row(destination: "7", buy: "1234567", sell: "1245678", created: "2026-11-06T11:00:00+05:00"), row(code: "JPY", buy: 8035, sell: 9012)])
        XCTAssertEqual(values.count, 3)
        let cash = try XCTUnwrap(values.first { $0.currency == "USD" && $0.channel == .cash })
        let app = try XCTUnwrap(values.first { $0.channel == .app })
        XCTAssertEqual(cash.buy, 12345); XCTAssertEqual(cash.sell, 12456)
        XCTAssertEqual(app.buy, Decimal(string: "12345.67")); XCTAssertEqual(app.sell, Decimal(string: "12456.78"))
        XCTAssertNotEqual(cash.publishedAt, app.publishedAt)
        XCTAssertEqual(cash.observedAt, now); XCTAssertTrue(cash.isCurrent(at: now))
        XCTAssertEqual(values.first { $0.currency == "JPY" }?.buy, Decimal(string: "80.35"))
        XCTAssertEqual(ExchangeAction.buy.rate(cash), cash.sell)
        XCTAssertEqual(ExchangeAction.sell.rate(cash), cash.buy)
        XCTAssertTrue(values.allSatisfy { $0.sourceURL == "https://hamkorbank.uz/exchange-rate/" && $0.bankID == "hamkorbank" })
    }
    func testConditionalRatesUnknownChannelsAndMetalsNeverBecomeGeneralOffers() throws {
        let values = try decode([row(), row(tier: 1000000, buy: 9999999), row(destination: "8"), row(code: "XAU", destination: "7")])
        XCTAssertEqual(values.count, 1); XCTAssertEqual(values.first?.buy, 12345)
        XCTAssertThrowsError(try decode([row(tier: 1000000)]))
        XCTAssertThrowsError(try decode([row(destination: "unknown")]))
    }
    func testMissingSideRemainsUnknownAndPublicationFreshnessIsNotReset() throws {
        let values = try decode([row(buy: NSNull()), row(code: "EUR", buy: 0, sell: -10), row(code: "GBP", created: "2026-11-01T12:00:00+05:00", effective: "2026-11-01T11:00:00+05:00")])
        XCTAssertNil(values.first?.buy); XCTAssertEqual(values.first?.sell, 12456)
        XCTAssertFalse(values.contains { $0.currency == "EUR" })
        XCTAssertFalse(try XCTUnwrap(values.first { $0.currency == "GBP" }).isCurrent(at: now))
        XCTAssertEqual(values.filter { $0.channel == .app }.count, 0)
    }
    func testFailuresDuplicateKeysAndFutureOrMalformedEffectiveDatesFailClosed() throws {
        XCTAssertThrowsError(try decode([row()], status: "Error"))
        XCTAssertThrowsError(try decode([row()], error: 1))
        XCTAssertThrowsError(try decode([row(), row()]))
        XCTAssertThrowsError(try decode([row(effective: "2026-11-07T12:00:00+05:00")]))
        XCTAssertThrowsError(try decode([row(created: "not a date")]))
        XCTAssertThrowsError(try BankProviders.decode("<html>Unavailable</html>", provider: "hamkor", at: now))
    }
    func testAggregateCanonicalIDAndDirectFailureFallback() throws {
        func entry(_ value: String) -> String {
            "<div class=\"bc-inner-block-left-texts\"><div><a href=\"/currency/bank/hamkorbank\"><span>Hamkorbank</span></a></div><span>\(value) сум</span></div>"
        }
        let html = "Лучшие курсы обмена валют в обменных пунктах<div id=\"best_USD\">Покупка" + entry("12 100") + "<div class=\"bc-inner-blocks-right\">Продажа" + entry("12 200")
        let aggregate = try BankProviders.decode(html, provider: "bankuz", at: now)
        XCTAssertEqual(aggregate.first?.bankID, "hamkorbank")
        let direct = try decode([row()])
        let normal = BankComparison.rows(quotes: aggregate + direct, currency: "USD", channel: .cash, action: .buy, amount: 1, at: now)
        XCTAssertEqual(normal.count, 1); XCTAssertEqual(normal.first?.quote.provider, "hamkor")
        let fallback = BankComparison.rows(quotes: aggregate + direct, currency: "USD", channel: .cash, action: .buy, amount: 1, failedProviders: ["hamkor"], at: now)
        XCTAssertEqual(fallback.first?.quote.provider, "bankuz")
    }
}
