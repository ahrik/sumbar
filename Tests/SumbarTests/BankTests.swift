import XCTest
@testable import Sumbar

final class BankTests: XCTestCase {
    private let now = Dates.parse("2026-11-06T12:00:00", pattern: "yyyy-MM-dd'T'HH:mm:ss")!
    private func quote(_ id: String, buy: Decimal?, sell: Decimal?, channel: BankChannel = .cash, provider: String = "ipak", age: TimeInterval = 0, publishedAge: TimeInterval = 0) -> BankQuote {
        BankQuote(bankID: id, bankName: id, currency: "USD", channel: channel, buy: buy, sell: sell, provider: provider, sourceURL: "https://example.com", publishedAt: now.addingTimeInterval(-publishedAge), observedAt: now.addingTimeInterval(-age))
    }
    func testCustomerBuysAtBankSellAndSellsAtBankBuy() {
        let quotes = [quote("A", buy: 100, sell: 120), quote("B", buy: 105, sell: 125)]
        let buy = BankComparison.rows(quotes: quotes, currency: "USD", channel: .cash, action: .buy, amount: 10, at: now)
        XCTAssertEqual(buy.first?.id, "A"); XCTAssertEqual(buy.first?.total, 1200)
        let sell = BankComparison.rows(quotes: quotes, currency: "USD", channel: .cash, action: .sell, amount: 10, at: now)
        XCTAssertEqual(sell.first?.id, "B"); XCTAssertEqual(sell.first?.total, 1050)
    }
    func testChannelsMissingSidesAndStaleDataDoNotWin() {
        let quotes = [quote("cash", buy: 100, sell: 120), quote("app", buy: 110, sell: 111, channel: .app), quote("old-check", buy: 90, sell: 91, age: 7201), quote("old-publication", buy: 80, sell: 81, publishedAge: 48 * 3600 + 1), quote("unknown", buy: 70, sell: nil)]
        let rows = BankComparison.rows(quotes: quotes, currency: "USD", channel: .cash, action: .buy, amount: 10, at: now)
        XCTAssertEqual(rows.first?.id, "cash"); XCTAssertEqual(rows.filter(\.eligible).count, 1)
        XCTAssertFalse(rows.contains { $0.id == "app" })
        XCTAssertNil(rows.first { $0.id == "unknown" }?.total)
    }
    func testDirectSourceWinsAndFailedDirectSourceFallsBack() {
        let direct = quote("same", buy: 100, sell: 120)
        let aggregate = quote("same", buy: 99, sell: 119, provider: "bankuz")
        let normal = BankComparison.rows(quotes: [aggregate, direct], currency: "USD", channel: .cash, action: .buy, amount: 1, at: now)
        XCTAssertEqual(normal.count, 1); XCTAssertEqual(normal.first?.quote.provider, "ipak")
        let failed = BankComparison.rows(quotes: [aggregate, direct], currency: "USD", channel: .cash, action: .buy, amount: 1, failedProviders: ["ipak"], at: now)
        XCTAssertEqual(failed.first?.quote.provider, "bankuz"); XCTAssertTrue(failed.first?.eligible == true)
    }
    func testInvalidAmountDoesNotBecomeZeroAndTiesStayDeterministic() {
        let rows = BankComparison.rows(quotes: [quote("B", buy: 100, sell: 120), quote("A", buy: 100, sell: 120)], currency: "USD", channel: .cash, action: .buy, amount: nil, at: now)
        XCTAssertEqual(rows.map(\.id), ["A", "B"]); XCTAssertNil(rows[0].total)
        let negative = BankComparison.rows(quotes: [quote("A", buy: 100, sell: 120)], currency: "USD", channel: .cash, action: .buy, amount: -1, at: now)
        XCTAssertNil(negative.first?.total)
        XCTAssertNil(ExchangeAction.buy.rate(quote("zero", buy: 100, sell: 0)))
    }
    func testOldCacheIsReadable() throws {
        let data = Data(#"{"currencies":[],"instruments":[],"observed":{},"currencyHistory":{},"details":{}}"#.utf8)
        let cache = try JSONDecoder().decode(CacheState.self, from: data)
        XCTAssertNil(cache.bankQuotes)
    }
    private func nuxt(_ object: Any) throws -> String {
        var values: [Any] = []
        func ref(_ node: Any) -> Int {
            let value: Any
            if let dictionary = node as? [String: Any] { value = dictionary.mapValues { ref($0) } }
            else if let array = node as? [Any] { value = array.map { ref($0) } }
            else { value = node }
            values.append(value); return values.count - 1
        }
        _ = ref(object)
        let data = try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])
        return "<script type=\"application/json\" id=\"__NUXT_DATA__\">" + String(decoding: data, as: UTF8.self) + "</script>"
    }
    func testIpakMinorUnitConversionAndMissingSide() throws {
        let html = try nuxt(["name":"В кассе", "lastUpdated": now.timeIntervalSince1970, "rates":[["code_name":"USD","rate":["buy":1234500,"sell":NSNull()]]]] as [String:Any])
        let quotes = try BankProviders.decode(html, provider: "ipak", at: now)
        XCTAssertEqual(quotes.count, 1); XCTAssertEqual(quotes[0].buy, 12345); XCTAssertNil(quotes[0].sell)
        XCTAssertEqual(quotes[0].publishedAt, now)
    }
    func testKapitalPrecisionIsNotCurrencyNominal() throws {
        let row: [String:Any] = ["currencyCode":"USD","buyRate":12345,"sellRate":12355,"scale":2,"lastUpdate":"2026-11-06T11:00:00"]
        let html = try nuxt(["physicalClients":["bankRate":row]])
        let quotes = try BankProviders.decode(html, provider: "kapital", at: now)
        XCTAssertEqual(quotes[0].buy, 12345); XCTAssertEqual(quotes[0].sell, 12355)
        XCTAssertEqual(quotes[0].channel, .cash)
    }
    func testBankUZCombinesBothSidesAndCanonicalizesBank() throws {
        func entry(_ price: String) -> String {
            "<div class=\"bc-inner-block-left-texts\"><div class=\"bc-inner-block-left-text\"><a href=\"/currency/bank/ipakyulibank\"><span class=\"medium-text\">Ipak Yuli Bank</span></a></div><span class=\"medium-text green-date\">\(price) сум</span></div>"
        }
        let html = "Лучшие курсы обмена валют в обменных пунктах<div id=\"best_USD\"><div>Покупка</div>" + entry("12 300") + "<div  class=\"bc-inner-blocks-right\">Продажа" + entry("12 400")
        let quotes = try BankProviders.decode(html, provider: "bankuz", at: now)
        XCTAssertEqual(quotes.count, 1); XCTAssertEqual(quotes[0].bankID, "ipak")
        XCTAssertEqual(quotes[0].buy, 12300); XCTAssertEqual(quotes[0].sell, 12400); XCTAssertNil(quotes[0].publishedAt)
        XCTAssertThrowsError(try BankProviders.decode("<html>Temporarily unavailable</html>", provider: "bankuz"))
    }
    func testLiveBankProvidersWhenRequested() async throws {
        guard ProcessInfo.processInfo.environment["SUMBAR_LIVE_TESTS"] == "1" else { throw XCTSkip("Live bank checks are opt-in") }
        for source in BankProviders.sources {
            let quotes: [BankQuote]
            do {
                if let directory = ProcessInfo.processInfo.environment["SUMBAR_BANK_FIXTURES"] {
                    let name = source.id == "kapital" ? "kapital-old" : source.id
                    let html = try String(contentsOfFile: directory + "/" + name + ".html", encoding: .utf8)
                    quotes = try BankProviders.decode(html, provider: source.id)
                } else { quotes = try await BankProviders.load(source) }
            } catch { XCTFail("\(source.name): \(error)"); continue }
            print("Bank provider \(source.name): \(quotes.count) quotes, \(Set(quotes.map(\.bankID)).count) banks")
            XCTAssertTrue(quotes.contains { $0.currency == "USD" && $0.buy != nil && $0.sell != nil }, source.name)
            XCTAssertEqual(Set(quotes.map(\.id)).count, quotes.count)
            if source.id == "bankuz" { XCTAssertGreaterThan(Set(quotes.map(\.bankID)).count, 10) }
            else { XCTAssertTrue(quotes.contains { $0.channel == .app }); XCTAssertTrue(quotes.contains { $0.channel == .cash }) }
        }
    }
}
