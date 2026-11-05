import XCTest
@testable import Sumbar

final class StartupTests: XCTestCase {
    @MainActor func testStartupRefreshWithLiveSourcesWhenRequested() async throws {
        guard ProcessInfo.processInfo.environment["SUMBAR_LIVE_TESTS"] == "1" else { throw XCTSkip("Startup integration is opt-in") }
        let store = MarketStore(inMemory: true)
        await store.refresh()
        XCTAssertFalse(store.loading)
        XCTAssertFalse(store.loadingBanks)
        XCTAssertNotNil(store.cache.fxChecked)
        XCTAssertNotNil(store.cache.stocksChecked)
        XCTAssertFalse(store.cache.bankQuotes?.isEmpty ?? true)
        XCTAssertTrue(store.bankErrors.isEmpty, String(describing: store.bankErrors))
        await store.refresh()
        XCTAssertFalse(store.loading)
        XCTAssertFalse(store.loadingBanks)
        XCTAssertNotNil(store.cache.fxChecked)
    }
}
