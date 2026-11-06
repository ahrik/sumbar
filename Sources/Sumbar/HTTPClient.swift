import Foundation

/// Shares provider backoff across its endpoints and retains validators only in memory.
actor MarketHTTPClient {
    private struct CachedResponse {
        let data: Data
        let etag: String?
        let modified: String?
    }
    private let session: URLSession
    private let clock: @Sendable () -> Date
    private var cached: [URL: CachedResponse] = [:]
    private var retryDates: [String: Date] = [:]

    init(session: URLSession = .shared, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.session = session; self.clock = clock
    }

    func data(_ url: URL) async throws -> Data {
        let host = url.host ?? url.absoluteString
        if let date = retryDates[host], date > clock() { throw RequestError.backoff(date) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Sumbar/0.2 (personal macOS market viewer)", forHTTPHeaderField: "User-Agent")
        if let previous = cached[url] {
            request.setValue(previous.etag, forHTTPHeaderField: "If-None-Match")
            request.setValue(previous.modified, forHTTPHeaderField: "If-Modified-Since")
        }
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw MarketError.invalidData }
        if response.statusCode == 429 || response.statusCode == 503 {
            let retry = Self.retryDate(response.value(forHTTPHeaderField: "Retry-After"), now: clock())
                ?? clock().addingTimeInterval(60)
            retryDates[host] = max(retryDates[host] ?? .distantPast, retry)
            throw RequestError.limited(response.statusCode, retry)
        }
        if response.statusCode == 304, let previous = cached[url] { return previous.data }
        guard response.statusCode == 200 else { throw MarketError.http(response.statusCode) }
        let etag = response.value(forHTTPHeaderField: "ETag")
        let modified = response.value(forHTTPHeaderField: "Last-Modified")
        if etag != nil || modified != nil {
            if cached[url] == nil, cached.count >= 64, let victim = cached.keys.first { cached.removeValue(forKey: victim) }
            cached[url] = CachedResponse(data: data, etag: etag, modified: modified)
        } else { cached.removeValue(forKey: url) }
        return data
    }

    static func retryDate(_ value: String?, now: Date) -> Date? {
        guard let value else { return nil }
        if let seconds = TimeInterval(value.trimmingCharacters(in: .whitespacesAndNewlines)), seconds.isFinite, seconds >= 0 {
            return now.addingTimeInterval(max(1, seconds))
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: value).map { max(now.addingTimeInterval(1), $0) }
    }
}

enum RequestError: LocalizedError {
    case limited(Int, Date), backoff(Date)
    var errorDescription: String? {
        switch self {
        case .limited(let code, let date): "Источник временно ограничил запросы (HTTP \(code)). Следующая попытка после \(Dates.display(date)), Ташкент."
        case .backoff(let date): "Источник просит подождать до \(Dates.display(date)), Ташкент. Сохранённые данные остаются доступны."
        }
    }
}
