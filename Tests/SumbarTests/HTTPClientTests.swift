import XCTest
@testable import Sumbar

private struct StubResponse: Sendable {
    let code: Int
    let headers: [String: String]
    var body = "synthetic"
}
private final class StubServer: @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [StubResponse] = []
    private var requests: [URLRequest] = []
    func reset(_ values: [StubResponse]) { lock.lock(); defer { lock.unlock() }; responses = values; requests = [] }
    func respond(_ request: URLRequest) -> StubResponse {
        lock.lock(); defer { lock.unlock() }
        requests.append(request)
        return responses.isEmpty ? StubResponse(code: 500, headers: [:]) : responses.removeFirst()
    }
    func received() -> [URLRequest] { lock.lock(); defer { lock.unlock() }; return requests }
}
private final class HTTPStub: URLProtocol, @unchecked Sendable {
    static let server = StubServer()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let stub = Self.server.respond(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: stub.code, httpVersion: "HTTP/1.1", headerFields: stub.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(stub.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class HTTPClientTests: XCTestCase {
    private func client(now: Date) -> MarketHTTPClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [HTTPStub.self]
        return MarketHTTPClient(session: URLSession(configuration: config), clock: { now })
    }
    func testConditionalRequestsReuseBodyOnNotModified() async throws {
        HTTPStub.server.reset([StubResponse(code: 200, headers: ["ETag": "\"test\"", "Last-Modified": "Fri, 06 Nov 2026 00:00:00 GMT"]), StubResponse(code: 304, headers: [:], body: "")])
        let client = client(now: Date())
        let url = URL(string: "https://conditional.test/data")!
        let first = try await client.data(url)
        let second = try await client.data(url)
        XCTAssertEqual(second, first)
        let requests = HTTPStub.server.received()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "If-None-Match"), "\"test\"")
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "If-Modified-Since"), "Fri, 06 Nov 2026 00:00:00 GMT")
    }
    func testRetryAfterBlocksOtherEndpointsWithoutSendingRequest() async throws {
        let now = Date()
        HTTPStub.server.reset([StubResponse(code: 429, headers: ["Retry-After": "120"])])
        let client = client(now: now)
        do { _ = try await client.data(URL(string: "https://limited.test/one")!); XCTFail("Expected limit") }
        catch RequestError.limited(let code, let retry) { XCTAssertEqual(code, 429); XCTAssertEqual(retry, now.addingTimeInterval(120)) }
        do { _ = try await client.data(URL(string: "https://limited.test/two")!); XCTFail("Expected backoff") }
        catch RequestError.backoff(let retry) { XCTAssertEqual(retry, now.addingTimeInterval(120)) }
        XCTAssertEqual(HTTPStub.server.received().count, 1)
    }
    func testServiceUnavailableAlsoSetsBackoffAndOtherHostStillWorks() async throws {
        HTTPStub.server.reset([StubResponse(code: 503, headers: [:]), StubResponse(code: 200, headers: [:])])
        let client = client(now: Date())
        do { _ = try await client.data(URL(string: "https://down.test/data")!); XCTFail("Expected unavailable") }
        catch RequestError.limited(let code, _) { XCTAssertEqual(code, 503) }
        let other = try await client.data(URL(string: "https://other.test/data")!)
        XCTAssertEqual(other, Data("synthetic".utf8))
    }
    func testRetryAfterAcceptsHTTPDateAndRejectsInvalidInput() {
        let now = Dates.parse("2026-11-06")!
        let retry = MarketHTTPClient.retryDate("Fri, 06 Nov 2026 01:00:00 GMT", now: now)
        XCTAssertEqual(retry, ISO8601DateFormatter().date(from: "2026-11-06T01:00:00Z"))
        XCTAssertNil(MarketHTTPClient.retryDate("NaN", now: now))
        XCTAssertNil(MarketHTTPClient.retryDate("-2", now: now))
        XCTAssertNil(MarketHTTPClient.retryDate("garbage", now: now))
    }
}
