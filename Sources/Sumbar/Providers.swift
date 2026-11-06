import Foundation

enum Providers {
    static let client = MarketHTTPClient()
    static func data(_ url: URL) async throws -> Data {
        try await client.data(url)
    }
    static func currencies(date: Date = Date()) async throws -> [CurrencyQuote] {
        try await CBUProvider.currencies(date: date, fetch: { try await data($0) })
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
        return try decodeDetail(await data(url))
    }
    static func decodeDetail(_ data: Data) throws -> SecurityDetail {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any], let rows = obj["history"] as? [[String: Any]] else { throw MarketError.invalidData }
        let points = rows.compactMap { row -> PricePoint? in
            guard let ds = row["date"] as? String, let date = Dates.parse(ds), let price = decimal(row["close"]), price > 0 else { return nil }
            return PricePoint(date: date, price: price)
        }.sorted { $0.date < $1.date }
        func positive(_ value: Any?) -> Decimal? { decimal(value).flatMap { $0 > 0 ? $0 : nil } }
        func nonnegative(_ value: Any?) -> Decimal? { decimal(value).flatMap { $0 >= 0 ? $0 : nil } }
        func day(_ value: Any?) -> String? { (value as? String).flatMap { Dates.parse($0) == nil ? nil : $0 } }
        var result = SecurityDetail(history: points, coupon: nonnegative(obj["coupon_rate_pct"]), faceValue: positive(obj["face_value"]))
        if let quote = obj["quote"] as? [String: Any] {
            result.session = SecuritySession(date: day(quote["trade_date"]), open: positive(quote["open"]), high: positive(quote["high"]), low: positive(quote["low"]), volume: nonnegative(quote["volume"]), turnover: nonnegative(quote["turnover"]), volumeUnit: obj["volume_unit"] as? String)
        }
        if let value = decimal(obj["coupon_frequency_per_year"]), value > 0, value <= 366, value == Decimal(NSDecimalNumber(decimal: value).intValue) { result.couponFrequency = NSDecimalNumber(decimal: value).intValue }
        result.issueDate = day(obj["issue_date"]); result.maturityDate = day(obj["maturity_date"])
        if let issuer = obj["issuer"] as? [String: Any] { result.issuerName = issuer["name"] as? String; result.sector = issuer["sector"] as? String }
        else { result.issuerName = obj["issuer"] as? String }
        result.priceBasis = obj["price_basis"] as? String
        var ids: Set<String> = []
        result.disclosures = (obj["disclosures"] as? [[String: Any]] ?? []).compactMap { item in
            guard let title = item["title"] as? String, !title.isEmpty, let link = item["url"] as? String, let url = URL(string: link), url.scheme == "https", let host = url.host?.lowercased(), ["openinfo.uz", "uzse.uz", "finmind.uz"].contains(where: { host == $0 || host.hasSuffix("." + $0) }) else { return nil }
            let disclosure = IssuerDisclosure(title: title, date: day(item["published_date"]), url: url)
            return ids.insert(disclosure.id).inserted ? disclosure : nil
        }
        return result
    }
}
import CoreFoundation
