import XCTest
@testable import Sumbar

private func syntheticCurrency(_ date: Date = Date()) -> CurrencyQuote {
    CurrencyQuote(code: "USD", name: "Доллар США", price: 12000, change: 0, effectiveDate: Dates.formatter("dd.MM.yyyy").string(from: date))
}

private actor LoadCounter {
    var counts: [String: Int] = [:]
    var failFX = false
    func hit(_ key: String) { counts[key, default: 0] += 1 }
    func setFXFailure() { failFX = true }
    func currencies(_ date: Date) throws -> [CurrencyQuote] {
        hit("fx")
        if failFX { throw MarketError.invalidData }
        return [syntheticCurrency(date)]
    }
}

final class OverviewTests: XCTestCase {
    @MainActor func testLegacySettingsMigrateAndFavoritesAndPinsSurviveRestart() throws {
        let name = "SumbarTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("EUR", forKey: "currency"); defaults.set(30, forKey: "refreshMinutes")
        let store = MarketStore(inMemory: true, defaults: defaults)
        XCTAssertEqual(store.selectedCurrency, "EUR"); XCTAssertEqual(store.refreshMinutes, 30)
        store.toggleCurrencyFavorite("CNY"); store.toggleBankFavorite("test-bank"); store.toggleInstrumentFavorite("bond:MISSING")
        store.selectedInstrumentID = "bond:MISSING"
        store.preferences.bankChannel = .app; store.preferences.bankAction = .sell
        store.pinBank("test-bank"); store.preferences.shortcut = .controlOptionS
        let restored = MarketStore(inMemory: true, defaults: defaults)
        XCTAssertEqual(restored.preferences, store.preferences)
        XCTAssertTrue(restored.preferences.favoriteCurrencies.contains("CNY"))
        XCTAssertEqual(restored.selectedInstrumentID, "bond:MISSING")
        XCTAssertTrue(restored.menuBarQuote().title.contains("—"))
        var invalid = restored.preferences
        invalid.refreshMinutes = -10
        defaults.set(try JSONEncoder().encode(invalid), forKey: "overviewPreferences")
        XCTAssertEqual(MarketStore(inMemory: true, defaults: defaults).refreshMinutes, 15)
    }

    @MainActor func testCurrencyMenuSeparatesCheckAndEffectiveDates() {
        let store = MarketStore(inMemory: true)
        let now = Date()
        store.cache.currencies = [syntheticCurrency(now)]; store.cache.fxChecked = now
        XCTAssertFalse(store.menuBarQuote(at: now).title.contains("—"))
        XCTAssertTrue(store.menuBarQuote(at: now).tooltip.contains("Действует с"))
        XCTAssertTrue(store.menuBarQuote(at: now.addingTimeInterval(1900)).title.contains("—"))
        store.cache.currencies = [syntheticCurrency(now.addingTimeInterval(2 * 86400))]
        XCTAssertTrue(store.menuBarQuote(at: now).title.contains("—"))
        store.cache.currencies = [syntheticCurrency(now)]; store.fxError = "Synthetic failure"
        XCTAssertTrue(store.menuBarQuote(at: now).title.contains("—"))
    }

    @MainActor func testPinnedBankKeepsSideChannelAndExcludesOldQuotes() {
        let store = MarketStore(inMemory: true)
        let now = Date()
        store.cache.bankQuotes = [
            BankQuote(bankID: "test", bankName: "Synthetic bank", currency: "USD", channel: .app, buy: 100, sell: 110, provider: "ipak", sourceURL: "https://example.test", publishedAt: now, observedAt: now),
            BankQuote(bankID: "test", bankName: "Synthetic bank", currency: "USD", channel: .cash, buy: 90, sell: 95, provider: "ipak", sourceURL: "https://example.test", publishedAt: now, observedAt: now)
        ]
        store.preferences.bankChannel = .app; store.preferences.bankAction = .buy; store.pinBank("test")
        store.preferences.bankChannel = .cash; store.preferences.bankAction = .sell
        XCTAssertEqual(store.menuBarQuote(at: now).title, "USD прил. купить 110")
        store.openPinnedQuote()
        XCTAssertEqual(store.preferences.bankChannel, .app); XCTAssertEqual(store.preferences.bankAction, .buy)
        store.bankErrors["ipak"] = "Synthetic failure"
        XCTAssertTrue(store.menuBarQuote(at: now).title.hasSuffix("—"))
        store.bankErrors = [:]
        XCTAssertTrue(store.menuBarQuote(at: now.addingTimeInterval(7201)).title.hasSuffix("—"))
    }

    @MainActor func testOldSecuritySessionIsLabeledAndMissingPinIsNotReplaced() async {
        let store = MarketStore(inMemory: true)
        let now = Date()
        let i = Instrument(key: "TEST", ticker: "TEST", name: "Synthetic", kind: "stock", currency: "UZS", price: 589, changePercent: nil, tradeDate: "2026-01-01")
        store.cache.instruments = [i]; store.cache.stocksChecked = now; store.pinInstrument(i.id)
        XCTAssertEqual(store.menuBarQuote(at: now).title, "TEST закр. 589")
        XCTAssertTrue(store.menuBarQuote(at: now).tooltip.contains("2026-01-01"))
        store.cache.instruments = []
        XCTAssertTrue(store.menuBarQuote(at: now).title.hasSuffix("—"))
        XCTAssertEqual(store.preferences.menuInstrumentID, i.id)
    }

    @MainActor func testAutomaticRefreshDoesNotRefetchOnEveryPanelOpenAndManualRefreshWorks() async {
        let counter = LoadCounter()
        let loaders = MarketLoaders(currencies: { try await counter.currencies($0) }, instruments: { await counter.hit("stocks"); return [] }, detail: { _ in SecurityDetail(history: [], coupon: nil, faceValue: nil) }, bank: { source in await counter.hit(source.id); return [] })
        let store = MarketStore(inMemory: true, loaders: loaders)
        await store.refresh(force: false)
        await store.refresh(force: false)
        let initial = await counter.counts
        XCTAssertEqual(initial["fx"], 1); XCTAssertEqual(initial["stocks"], 1)
        XCTAssertEqual(initial["ipak"], 1); XCTAssertEqual(initial["kapital"], 1); XCTAssertEqual(initial["bankuz"], 1)
        await counter.setFXFailure()
        await store.refresh()
        XCTAssertNotNil(store.fxError); XCTAssertEqual(store.cache.currencies.count, 1)
        let manual = await counter.counts
        XCTAssertEqual(manual["fx"], 2); XCTAssertEqual(manual["stocks"], 2)
    }

    @MainActor func testHistoryFailuresRemainIndependentAndCacheIsPreserved() async {
        let loaders = MarketLoaders(currencies: { _ in throw MarketError.invalidData }, detail: { _ in throw MarketError.http(503) })
        let store = MarketStore(inMemory: true, loaders: loaders)
        let i = Instrument(key: "TEST", ticker: "TEST", name: "Synthetic", kind: "stock", currency: "UZS", price: 1, changePercent: nil, tradeDate: nil)
        let old = PricePoint(date: Date(), price: 1)
        store.cache.currencyHistory["USD"] = [old]
        store.cache.details[i.id] = SecurityDetail(history: [old], coupon: nil, faceValue: nil)
        await store.loadCurrencyHistory()
        await store.loadDetail(i, force: true)
        XCTAssertNotNil(store.currencyHistoryError); XCTAssertNotNil(store.securityHistoryErrors[i.id])
        XCTAssertEqual(store.cache.currencyHistory["USD"]?.count, 1)
        XCTAssertEqual(store.cache.details[i.id]?.history.count, 1)
        XCTAssertFalse(store.loadingChart)
    }
}
