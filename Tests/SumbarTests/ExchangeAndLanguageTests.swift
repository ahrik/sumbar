import XCTest
@testable import Sumbar

final class ExchangeAndLanguageTests: XCTestCase {
    func testUZSBudgetAndTargetUseCorrectCustomerSideWithDecimalPrecision() {
        let q = BankQuote(bankID: "test", bankName: "Synthetic", currency: "USD", channel: .cash, buy: 100, sell: 125, provider: "ipak", sourceURL: "https://example.test", publishedAt: Date(), observedAt: Date())
        XCTAssertEqual(ExchangeAmountMode.uzs.result(amount: 1000, rate: ExchangeAction.buy.rate(q)), 8)
        XCTAssertEqual(ExchangeAmountMode.uzs.result(amount: 1000, rate: ExchangeAction.sell.rate(q)), 10)
        XCTAssertEqual(ExchangeAmountMode.foreign.result(amount: 10, rate: ExchangeAction.buy.rate(q)), 1250)
        XCTAssertNil(ExchangeAmountMode.uzs.result(amount: -1, rate: 125))
        XCTAssertNil(ExchangeAmountMode.uzs.result(amount: 1000, rate: 0))
        XCTAssertNil(ExchangeAmountMode.uzs.result(amount: nil, rate: 125))
    }
    func testBothCataloguesHaveMatchingKeysAndFormatArguments() throws {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/Sumbar/Resources")
        func catalogue(_ language: String) throws -> [String: String] {
            let data = try Data(contentsOf: source.appendingPathComponent("\(language).lproj/Localizable.strings"))
            return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
        }
        let ru = try catalogue("ru"); let uz = try catalogue("uz")
        XCTAssertEqual(Set(ru.keys), Set(uz.keys)); XCTAssertGreaterThan(uz.count, 250)
        for (key, value) in uz { XCTAssertEqual(key.components(separatedBy: "%@").count, value.components(separatedBy: "%@").count, key) }
    }
    @MainActor func testLanguageSwitchPreservesPreferencesAndInterpolatesValues() throws {
        let name = "SumbarTests.\(UUID().uuidString)"; let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = MarketStore(inMemory: true, defaults: defaults)
        store.preferences.menuCurrency = "EUR"; store.language = .uz
        XCTAssertEqual(store.l10n("Настройки"), "Sozlamalar")
        XCTAssertEqual(store.l10n("Сумма в \("USD")"), "USD hisobidagi summa")
        let restored = MarketStore(inMemory: true, defaults: defaults)
        XCTAssertEqual(restored.language, .uz); XCTAssertEqual(restored.preferences.menuCurrency, "EUR")
        let quote = CurrencyQuote(code: "USD", name: "Доллар", price: 1, change: 0, effectiveDate: "06.11.2026", nameUz: "AQSH dollari")
        XCTAssertEqual(restored.currencyName(quote), "AQSH dollari")
    }
    @MainActor func testMenuTooltipUsesSelectedLanguageAndUzbekCurrencyNameDecodes() throws {
        let bytes = Data(#"[{"Ccy":"USD","CcyNm_RU":"Доллар","CcyNm_UZ":"AQSH dollari","Nominal":"1","Rate":"12000","Diff":"0","Date":"06.11.2026"}]"#.utf8)
        let quote = try JSONDecoder().decode([CBURecord].self, from: bytes)[0].quote()
        XCTAssertEqual(quote.nameUz, "AQSH dollari")
        let store = MarketStore(inMemory: true); store.language = .uz
        let now = Dates.parse("2026-11-06")!.addingTimeInterval(60)
        store.cache.fxChecked = now; store.cache.currencies = [quote]
        let menu = store.menuBarQuote(at: now)
        XCTAssertTrue(menu.title.contains("MB")); XCTAssertTrue(menu.tooltip.contains("Tekshirildi"))
        XCTAssertNil(menu.tooltip.range(of: "[А-Яа-яЁё]", options: .regularExpression))
    }

}
