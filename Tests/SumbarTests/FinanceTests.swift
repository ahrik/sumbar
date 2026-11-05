import XCTest
@testable import Sumbar

final class FinanceTests: XCTestCase {
    func testLiveProvidersWhenRequested() async throws {
        guard ProcessInfo.processInfo.environment["SUMBAR_LIVE_TESTS"] == "1" else { throw XCTSkip("Set SUMBAR_LIVE_TESTS=1 for live provider checks") }
        let currencies = try await Providers.currencies()
        XCTAssertTrue(currencies.contains { $0.code == "USD" && $0.price > 0 })
        let instruments = try await Providers.instruments()
        let stock = try XCTUnwrap(instruments.first { $0.ticker == "AGBA" })
        let detail = try await Providers.detail(stock)
        XCTAssertFalse(detail.history.isEmpty)
        if let bond = instruments.first(where: { $0.kind == "bond" }) {
            let bondDetail = try await Providers.detail(bond)
            XCTAssertNotNil(bondDetail.faceValue)
        }
    }
    func testDecimalRoundTripAndFeeOnBothSides() throws {
        let result = Money.investment(quantity: 10, entry: 100, exit: 120, fee: 1)
        XCTAssertEqual(result.cost, 1010)
        XCTAssertEqual(result.proceeds, 1188)
        XCTAssertEqual(result.profit, 178)
        XCTAssertEqual(Money.parse("1 234,56"), Decimal(string: "1234.56"))
        XCTAssertNil(Money.parse("NaN")); XCTAssertNil(Money.parse("12oops"))
    }
    func testNominalNormalization() throws {
        let data = Data(#"[{"Ccy":"JPY","CcyNm_RU":"Иена","Nominal":"100","Rate":"8000.50","Diff":"20","Date":"06.11.2026"}]"#.utf8)
        let record = try JSONDecoder().decode([CBURecord].self, from: data)[0]
        let quote = try record.quote()
        XCTAssertEqual(quote.price, Decimal(string: "80.005"))
        XCTAssertEqual(quote.change, Decimal(string: "0.2"))
    }
    func testMissingMarketPriceDoesNotBecomeZero() throws {
        let data = Data(#"{"stocks":[{"ticker":"TEST","isin":"TEST0001","name":"Synthetic test","last":null,"change_pct":null}],"bonds":[]}"#.utf8)
        let instruments = try Providers.decodeInstruments(data)
        XCTAssertNil(instruments[0].price); XCTAssertNil(instruments[0].changePercent)
    }
    func testWrongSchemaAndZeroNominalAreRejected() throws {
        XCTAssertThrowsError(try Providers.decodeInstruments(Data("{}".utf8)))
        let record = CBURecord(Ccy:"JPY", CcyNm_RU:"Иена", Nominal:"0", Rate:"1", Diff:"0", Date:"06.11.2026")
        XCTAssertThrowsError(try record.quote())
    }
    func testDateUsesTashkentDay() {
        let instant = ISO8601DateFormatter().date(from:"2026-11-05T20:30:00Z")!
        XCTAssertEqual(Dates.day(instant), "2026-11-06")
    }
}
