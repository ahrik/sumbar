import XCTest
@testable import Sumbar

private actor CBUStub {
    private var responses: [Result<Data, any Error>]
    private(set) var requests: [URL] = []
    init(_ responses: [Result<Data, any Error>]) { self.responses = responses }
    func fetch(_ url: URL) throws -> Data {
        requests.append(url)
        guard !responses.isEmpty else { throw URLError(.badServerResponse) }
        return try responses.removeFirst().get()
    }
}

final class CBUProviderTests: XCTestCase {
    private let day = Dates.parse("2026-10-31")!
    private let body = Data(#"[{"Ccy":"JPY","CcyNm_RU":"Иена","Nominal":"100","Rate":"8000.50","Diff":"20","Date":"30.10.2026"}]"#.utf8)

    func testPrimarySuccessUsesOnlyOneRequestAndNormalizesNominal() async throws {
        let server = CBUStub([.success(body)])
        let quotes = try await CBUProvider.currencies(date: day, fetch: { try await server.fetch($0) })
        XCTAssertEqual(quotes.first?.price, Decimal(string: "80.005"))
        let urls = await server.requests
        XCTAssertEqual(urls.map(\.host), ["cbu.uz"])
        XCTAssertEqual(urls.first?.path, "/ru/arkhiv-kursov-valyut/json/all/2026-10-31")
    }

    func testConnectionFailuresTryOnlyTheOfficialHTTPSAliasAndKeepDate() async throws {
        for code: URLError.Code in [.serverCertificateUntrusted, .serverCertificateHasBadDate, .secureConnectionFailed, .cannotFindHost, .timedOut] {
            let server = CBUStub([.failure(URLError(code)), .success(body)])
            let quotes = try await CBUProvider.currencies(date: day, fetch: { try await server.fetch($0) })
            XCTAssertEqual(quotes.first?.effectiveDate, "30.10.2026")
            let urls = await server.requests
            XCTAssertEqual(urls.map(\.absoluteString), [
                "https://cbu.uz/ru/arkhiv-kursov-valyut/json/all/2026-10-31/",
                "https://www.cbu.uz/ru/arkhiv-kursov-valyut/json/all/2026-10-31/"
            ])
        }
    }

    func testHTTPBackoffCancellationAndOfflineErrorsAreNotRetried() async throws {
        let retry = Date().addingTimeInterval(120)
        let errors: [any Error] = [MarketError.http(404), RequestError.limited(429, retry), RequestError.limited(503, retry), RequestError.backoff(retry), URLError(.cancelled), URLError(.notConnectedToInternet), CancellationError()]
        for error in errors {
            let server = CBUStub([.failure(error), .success(body)])
            do { _ = try await CBUProvider.currencies(date: day, fetch: { try await server.fetch($0) }); XCTFail("Expected original error") }
            catch { XCTAssertFalse(error is CBUConnectionError) }
            let count = await server.requests.count
            XCTAssertEqual(count, 1)
        }
    }

    func testInvalidDataDoesNotTriggerAnotherSourceOrBecomeAQuote() async throws {
        for data in [Data("broken".utf8), Data("[]".utf8), Data(#"[{"Ccy":"JPY","CcyNm_RU":"Иена","Nominal":"0","Rate":"1","Diff":"0","Date":"30.10.2026"}]"#.utf8)] {
            let server = CBUStub([.success(data), .success(body)])
            do { _ = try await CBUProvider.currencies(date: day, fetch: { try await server.fetch($0) }); XCTFail("Expected data error") }
            catch { XCTAssertFalse(error is CBUConnectionError) }
            let count = await server.requests.count
            XCTAssertEqual(count, 1)
        }
    }

    func testBothCertificateFailuresStopAndExplainTheSourceInBothLanguages() async throws {
        let server = CBUStub([.failure(URLError(.serverCertificateUntrusted)), .failure(URLError(.serverCertificateHasUnknownRoot)), .success(body)])
        do { _ = try await CBUProvider.currencies(date: day, fetch: { try await server.fetch($0) }); XCTFail("Untrusted servers must fail") }
        catch CBUConnectionError.certificate {
            XCTAssertTrue(L10n(language: .ru).error(CBUConnectionError.certificate).contains("сертификат ЦБ"))
            XCTAssertTrue(L10n(language: .uz).error(CBUConnectionError.certificate).contains("Markaziy bank"))
        }
        let count = await server.requests.count
        XCTAssertEqual(count, 2)
    }

    func testAlternateFailurePreservesRateLimitAndDistinguishesTLSFromCertificateErrors() async throws {
        let retry = Date().addingTimeInterval(120)
        let limited = CBUStub([.failure(URLError(.cannotFindHost)), .failure(RequestError.limited(429, retry)), .success(body)])
        do { _ = try await CBUProvider.currencies(date: day, fetch: { try await limited.fetch($0) }); XCTFail("Expected backoff") }
        catch RequestError.limited(let code, let date) { XCTAssertEqual(code, 429); XCTAssertEqual(date, retry) }
        let count = await limited.requests.count
        XCTAssertEqual(count, 2)
        let tls = CBUStub([.failure(URLError(.secureConnectionFailed)), .failure(URLError(.secureConnectionFailed))])
        do { _ = try await CBUProvider.currencies(date: day, fetch: { try await tls.fetch($0) }); XCTFail("Expected TLS error") }
        catch CBUConnectionError.tls { XCTAssertTrue(L10n(language: .uz).error(CBUConnectionError.tls).contains("xavfsiz")) }
    }

    func testCancellationAfterPrimaryFailureStopsBeforeAlternateRequest() async throws {
        let server = CBUStub([.failure(URLError(.serverCertificateUntrusted)), .success(body)])
        let requested = day
        let task = Task {
            try await CBUProvider.currencies(date: requested, fetch: { url in
                do { return try await server.fetch(url) }
                catch { withUnsafeCurrentTask { $0?.cancel() }; throw error }
            })
        }
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch is CancellationError {}
        let count = await server.requests.count
        XCTAssertEqual(count, 1)
    }

    func testLiveCBUHistoryWhenRequested() async throws {
        guard ProcessInfo.processInfo.environment["SUMBAR_LIVE_TESTS"] == "1" else { throw XCTSkip("CBU integration is opt-in") }
        let today = Date()
        for requested in [today, Dates.calendar.date(byAdding: .day, value: -7, to: today)!] {
            let quotes = try await Providers.currencies(date: requested)
            let snapshot = try FXSnapshot.validated(quotes: quotes, requested: requested, checkedAt: Date())
            XCTAssertNotNil(snapshot.quote("USD"))
            XCTAssertNotNil(snapshot.quote("EUR"))
            XCTAssertEqual(snapshot.quotes.count, quotes.count)
        }
    }
}
