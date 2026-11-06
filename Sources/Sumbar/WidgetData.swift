import Foundation

/// Shared source, compiled into both the app and its sandboxed widget extension.
struct WidgetRateSnapshot: Codable, Sendable {
    let quotes: [CurrencyQuote]
    let checkedAt: Date

    func quote(_ code: String, at now: Date) -> CurrencyQuote? {
        quotes.first {
            guard $0.code == code, $0.price > 0,
                  let effective = Dates.parse($0.effectiveDate, pattern: "dd.MM.yyyy") else { return false }
            return effective <= now.addingTimeInterval(300) && now.timeIntervalSince(effective) < 8 * 86400
        }
    }

    func isFresh(at now: Date) -> Bool {
        (-300...3600).contains(now.timeIntervalSince(checkedAt))
    }

    /// Pre-render the stale and expired states even if macOS postpones our next network refresh.
    func nextChange(after now: Date) -> Date? {
        ([checkedAt.addingTimeInterval(3601)] + quotes.compactMap {
            Dates.parse($0.effectiveDate, pattern: "dd.MM.yyyy")?.addingTimeInterval(8 * 86400)
        }).filter { $0 > now }.min()
    }
}

struct WidgetRateResult: Sendable {
    let snapshot: WidgetRateSnapshot?
    let failed: Bool
}

actor WidgetRateStore {
    typealias Loader = @Sendable (Date) async throws -> [CurrencyQuote]
    private let fileURL: URL?
    private let loader: Loader
    private var snapshot: WidgetRateSnapshot?
    private var inFlight: Task<WidgetRateSnapshot, Error>?
    private var canWrite = true

    init(fileURL: URL?, loader: @escaping Loader) {
        self.fileURL = fileURL
        self.loader = loader
        if let fileURL, FileManager.default.fileExists(atPath: fileURL.path) {
            do { snapshot = try JSONDecoder().decode(WidgetRateSnapshot.self, from: Data(contentsOf: fileURL)) }
            catch { canWrite = false } // Preserve unreadable files; an online result can still be used in memory.
        }
    }

    func cached() -> WidgetRateSnapshot? { snapshot }

    func refresh(at now: Date = Date()) async -> WidgetRateResult {
        if let snapshot, (-300..<900).contains(now.timeIntervalSince(snapshot.checkedAt)) {
            return WidgetRateResult(snapshot: snapshot, failed: false)
        }
        let task: Task<WidgetRateSnapshot, Error>
        if let inFlight { task = inFlight }
        else {
            let loader = self.loader
            task = Task {
                let quotes = try await loader(now)
                try Task.checkCancellation()
                guard !quotes.isEmpty else { throw MarketError.invalidData }
                return WidgetRateSnapshot(quotes: quotes, checkedAt: now)
            }
            inFlight = task
        }
        do {
            let loaded = try await task.value
            snapshot = loaded; inFlight = nil
            if canWrite, let fileURL {
                // A failed disk write must not discard the successfully fetched in-memory rates.
                try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? JSONEncoder().encode(loaded).write(to: fileURL, options: .atomic)
            }
            return WidgetRateResult(snapshot: loaded, failed: false)
        } catch {
            inFlight = nil
            return WidgetRateResult(snapshot: snapshot, failed: true)
        }
    }
}

enum WidgetLink {
    static func url(currency: String) -> URL {
        var parts = URLComponents()
        parts.scheme = "sumbar"; parts.host = "currency"
        parts.queryItems = [URLQueryItem(name: "code", value: currency)]
        return parts.url!
    }

    static func currency(from url: URL) -> String? {
        guard url.scheme == "sumbar", url.host == "currency", url.path.isEmpty,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = parts.queryItems?.first(where: { $0.name == "code" })?.value,
              code.range(of: "^[A-Z]{3}$", options: .regularExpression) != nil else { return nil }
        return code
    }
}
