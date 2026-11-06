import Foundation

enum Providers {
    static let client = MarketHTTPClient()
    static func data(_ url: URL) async throws -> Data {
        try await client.data(url)
    }
    static func currencies(date: Date = Date()) async throws -> [CurrencyQuote] {
        // Explicit date: the CBU's parameterless URL has different default semantics.
        let url = URL(string: "https://cbu.uz/ru/arkhiv-kursov-valyut/json/all/\(Dates.day(date))/")!
        let records = try JSONDecoder().decode([CBURecord].self, from: await data(url))
        let quotes = try records.map { try $0.quote() }
        guard !quotes.isEmpty else { throw MarketError.invalidData }; return quotes
    }
    static func decimal(_ value: Any?) -> Decimal? {
        if let s = value as? String { return Money.parse(s) }
        if let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { return n.decimalValue }
        return nil
    }
    static func decodeInstruments(_ data: Data) throws -> [Instrument] {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any], let stocks = obj["stocks"] as? [[String: Any]], let bonds = obj["bonds"] as? [[String: Any]] else { throw MarketError.invalidData }
        let result = [("stock", stocks), ("bond", bonds)].flatMap { kind, rows in
            rows.compactMap { row -> Instrument? in
                guard let ticker = row["ticker"] as? String, let isin = row["isin"] as? String else { return nil }
                let last = decimal(row["last"])
                return Instrument(key: kind == "stock" ? ticker : isin, ticker: ticker, name: (row["name"] as? String) ?? (row["issuer"] as? String) ?? ticker, kind: kind, currency: (row["currency"] as? String) ?? "UZS", price: last.flatMap { $0 > 0 ? $0 : nil }, changePercent: decimal(row["change_pct"]), tradeDate: row["trade_date"] as? String)
            }
        }
        guard !result.isEmpty else { throw MarketError.invalidData }; return result
    }
    static func instruments() async throws -> [Instrument] {
        try decodeInstruments(await data(URL(string: "https://finmind.uz/api/v1/public/market/instruments/")!))
    }
    static func detail(_ instrument: Instrument) async throws -> SecurityDetail {
        let group = instrument.kind == "stock" ? "stocks" : "bonds"
        let url = URL(string: "https://finmind.uz/api/v1/public/market/\(group)/")!.appendingPathComponent(instrument.key).appendingPathComponent("")
        guard let obj = try JSONSerialization.jsonObject(with: await data(url)) as? [String: Any], let rows = obj["history"] as? [[String: Any]] else { throw MarketError.invalidData }
        let points = rows.compactMap { row -> PricePoint? in
            guard let ds = row["date"] as? String, let date = Dates.parse(ds), let price = decimal(row["close"]), price > 0 else { return nil }
            return PricePoint(date: date, price: price)
        }.sorted { $0.date < $1.date }
        return SecurityDetail(history: points, coupon: decimal(obj["coupon_rate_pct"]), faceValue: decimal(obj["face_value"]))
    }
}
import CoreFoundation
