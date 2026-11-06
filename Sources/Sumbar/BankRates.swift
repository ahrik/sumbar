import Foundation

// Prices are UZS for one foreign-currency unit. The bank's sides are retained.
enum BankChannel: String, Codable, CaseIterable, Identifiable, Sendable {
    case cash, app, atm
    var id: String { rawValue }
    var title: String { switch self { case .cash: "В кассе"; case .app: "В приложении"; case .atm: "В банкомате" } }
}
enum ExchangeAction: String, Codable, CaseIterable, Identifiable, Sendable {
    case buy, sell
    var id: String { rawValue }
    func rate(_ quote: BankQuote) -> Decimal? {
        let value = self == .buy ? quote.sell : quote.buy
        return value.flatMap { $0 > 0 ? $0 : nil }
    }
}
struct BankQuote: Codable, Identifiable, Sendable {
    let bankID: String
    let bankName: String
    let currency: String
    let channel: BankChannel
    let buy: Decimal?
    let sell: Decimal?
    let provider: String
    let sourceURL: String
    let publishedAt: Date?
    let observedAt: Date
    var id: String { provider + ":" + bankID + ":" + currency + ":" + channel.rawValue }
    var sourceName: String { provider == "bankuz" ? "Bank.uz" : "Сайт банка" }
    func isCurrent(at now: Date) -> Bool {
        let age = now.timeIntervalSince(observedAt)
        guard age >= -300, age <= 2 * 3600 else { return false }
        // A successful check does not make an old publication new.
        if let publishedAt {
            let sourceAge = now.timeIntervalSince(publishedAt)
            guard sourceAge >= -300, sourceAge <= 48 * 3600 else { return false }
        }
        return true
    }
}
struct BankRow: Identifiable {
    let quote: BankQuote
    let rate: Decimal?
    let total: Decimal?
    let eligible: Bool
    var id: String { quote.bankID }
}
enum ExchangeAmountMode: String, CaseIterable, Identifiable {
    case foreign, uzs
    var id: String { rawValue }
    func result(amount: Decimal?, rate: Decimal?) -> Decimal? {
        guard let amount, amount >= 0, amount <= 1_000_000_000_000, let rate, rate > 0 else { return nil }
        return self == .uzs ? amount / rate : amount * rate
    }
}
enum BankComparison {
    static func rows(quotes: [BankQuote], currency: String, channel: BankChannel, action: ExchangeAction, amount: Decimal?, failedProviders: Set<String> = [], at now: Date = Date()) -> [BankRow] {
        let amount = amount.flatMap { $0 >= 0 && $0 <= 1_000_000_000_000 ? $0 : nil }
        let grouped = Dictionary(grouping: quotes.filter { $0.currency == currency && $0.channel == channel }, by: \.bankID)
        let rows = grouped.values.compactMap { alternatives -> BankRow? in
            let sorted = alternatives.sorted { a, b in
                let aOK = a.isCurrent(at: now) && !failedProviders.contains(a.provider) && action.rate(a) != nil
                let bOK = b.isCurrent(at: now) && !failedProviders.contains(b.provider) && action.rate(b) != nil
                if aOK != bOK { return aOK }
                if (a.provider == "bankuz") != (b.provider == "bankuz") { return a.provider != "bankuz" }
                return a.observedAt > b.observedAt
            }
            guard let quote = sorted.first else { return nil }
            let rate = action.rate(quote)
            let eligible = quote.isCurrent(at: now) && !failedProviders.contains(quote.provider) && rate != nil
            return BankRow(quote: quote, rate: rate, total: amount.flatMap { n in rate.map { n * $0 } }, eligible: eligible)
        }
        return rows.sorted { a, b in
            if a.eligible != b.eligible { return a.eligible }
            if a.eligible, let x = a.rate, let y = b.rate, x != y { return action == .buy ? x < y : x > y }
            return a.quote.bankName.localizedStandardCompare(b.quote.bankName) == .orderedAscending
        }
    }
}

/// Each site adapter fails closed if the expected currency tables disappear.
/// Cached HTML and actual rate fixtures are never checked into Git.
enum BankProviders {
    struct Source: Sendable {
        let id: String; let name: String; let url: String
        var requestURL: String? = nil
    }
    static let sources = [
        Source(id: "ipak", name: "Ipak Yuli Bank", url: "https://ru.ipakyulibank.uz/physical/obmen-valyut"),
        Source(id: "kapital", name: "Kapitalbank", url: "https://www.kapitalbank.uz/ru/services/exchange-rates-new/"),
        Source(id: "bankuz", name: "Bank.uz", url: "https://bank.uz/currency"),
        Source(id: "hamkor", name: "Hamkorbank", url: "https://hamkorbank.uz/exchange-rate/", requestURL: "https://api-dbo.hamkorbank.uz/webflow/v1/exchanges")
    ]
    static func load(_ source: Source) async throws -> [BankQuote] {
        let data = try await Providers.data(URL(string: source.requestURL ?? source.url)!)
        guard let html = String(data: data, encoding: .utf8) else { throw MarketError.invalidData }
        return try decode(html, provider: source.id)
    }
    static func matches(_ pattern: String, _ text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { result in
            (0..<result.numberOfRanges).map { index in Range(result.range(at: index), in: text).map { String(text[$0]) } ?? "" }
        }
    }
    private static func split(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [text] }
        let source = text as NSString
        var start = 0; var pieces: [String] = []
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            pieces.append(source.substring(with: NSRange(location: start, length: match.range.location - start)))
            start = NSMaxRange(match.range)
        }
        pieces.append(source.substring(from: start)); return pieces
    }
    static func clean(_ text: String) -> String {
        var value = text
        for (from, to) in [("&nbsp;", " "), ("&#160;", " "), ("&amp;", "&"), ("&#39;", "'"), ("&quot;", "\"")] { value = value.replacingOccurrences(of: from, with: to) }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private static func validPrice(_ value: Any?) -> Decimal? { Providers.decimal(value).flatMap { $0 > 0 ? $0 : nil } }
    private static func bankID(_ slug: String) -> String {
        if slug == "kapitalbank" { return "kapital" }
        if ["hamkorbank", "hamkor-bank", "hamkor"].contains(slug) { return "hamkorbank" }
        if ["ipak-yuli-bank", "ipak-yuli", "ipakyuli", "ipakyulibank"].contains(slug) { return "ipak" }
        return slug
    }
    static func decode(_ html: String, provider: String, at now: Date = Date()) throws -> [BankQuote] {
        let quotes: [BankQuote]
        switch provider {
        case "ipak": quotes = try decodeIpak(html, at: now)
        case "kapital": quotes = try decodeKapital(html, at: now)
        case "bankuz": quotes = decodeBankUZ(html, at: now)
        case "hamkor": quotes = try decodeHamkor(Data(html.utf8), at: now)
        default: throw MarketError.invalidData
        }
        guard !quotes.isEmpty, quotes.contains(where: { $0.currency == "USD" }) else { throw MarketError.invalidData }
        guard Set(quotes.map(\.id)).count == quotes.count else { throw MarketError.invalidData }
        return quotes
    }
    private static func payload(_ html: String) throws -> [Any] {
        guard let script = matches(#"<script\b[^>]*\bid="__NUXT_DATA__"[^>]*>(.*?)</script>"#, html).first,
              let data = script[1].data(using: .utf8), let values = try JSONSerialization.jsonObject(with: data) as? [Any] else { throw MarketError.invalidData }
        return values
    }
    // Nuxt/devalue stores object fields and array entries as references, including numeric values.
    private static func resolved(_ node: Any, values: [Any], depth: Int = 0) -> Any {
        guard depth < 20 else { return NSNull() }
        func dereference(_ reference: Any) -> Any {
            guard let index = reference as? Int, values.indices.contains(index) else { return NSNull() }
            return resolved(values[index], values: values, depth: depth + 1)
        }
        if let object = node as? [String: Any] { return object.mapValues(dereference) }
        if let array = node as? [Any] { return array.map(dereference) }
        return node
    }
    private static func decodeIpak(_ html: String, at now: Date) throws -> [BankQuote] {
        let values = try payload(html)
        var quotes: [BankQuote] = []
        for node in values {
            guard let object = node as? [String: Any], object["rates"] != nil, object["lastUpdated"] != nil,
                  let table = resolved(node, values: values) as? [String: Any], let name = table["name"] as? String,
                  let channel = BankChannel.allCases.first(where: { $0.title == name }), let rows = table["rates"] as? [[String: Any]],
                  let timestamp = table["lastUpdated"] as? NSNumber, timestamp.doubleValue > 0 else { continue }
            for row in rows {
                guard let currency = row["code_name"] as? String, currency.range(of: #"^[A-Z]{3}$"#, options: .regularExpression) != nil, let rates = row["rate"] as? [String: Any] else { continue }
                let buy = validPrice(rates["buy"]).map { $0 / 100 }
                let sell = validPrice(rates["sell"]).map { $0 / 100 }
                guard buy != nil || sell != nil else { continue }
                quotes.append(BankQuote(bankID: "ipak", bankName: "Ipak Yuli Bank", currency: currency, channel: channel, buy: buy, sell: sell, provider: "ipak", sourceURL: sources[0].url, publishedAt: Date(timeIntervalSince1970: timestamp.doubleValue), observedAt: now))
            }
        }
        return quotes
    }
    private static func decodeKapital(_ html: String, at now: Date) throws -> [BankQuote] {
        let values = try payload(html)
        var quotes: [BankQuote] = []
        for node in values {
            guard let object = node as? [String: Any], let reference = object["physicalClients"] as? Int, values.indices.contains(reference),
                  let physical = resolved(values[reference], values: values) as? [String: Any] else { continue }
            for (key, channel) in [("bankRate", BankChannel.cash), ("applicationRate", .app), ("atmRate", .atm)] {
                guard let row = physical[key] as? [String: Any], let currency = row["currencyCode"] as? String,
                      currency.range(of: #"^[A-Z]{3}$"#, options: .regularExpression) != nil,
                      let ds = row["lastUpdate"] as? String, let published = Dates.parse(ds, pattern: "yyyy-MM-dd'T'HH:mm:ss") else { continue }
                // scale is display precision, not the currency nominal. Rates already are per unit.
                let buy = validPrice(row["buyRate"]); let sell = validPrice(row["sellRate"])
                guard buy != nil || sell != nil else { continue }
                quotes.append(BankQuote(bankID: "kapital", bankName: "Kapitalbank", currency: currency, channel: channel, buy: buy, sell: sell, provider: "kapital", sourceURL: sources[1].url, publishedAt: published, observedAt: now))
            }
        }
        return quotes
    }
    private static func decodeBankUZ(_ html: String, at now: Date) -> [BankQuote] {
        guard html.contains("Лучшие курсы обмена валют в обменных пунктах") else { return [] }
        let sections = html.components(separatedBy: "id=\"best_").dropFirst()
        var result: [BankQuote] = []
        for section in sections {
            let currency = String(section.prefix(3))
            guard ["USD", "EUR", "RUB", "GBP", "CHF"].contains(currency) else { continue }
            let sides = split(#"<div\s+class="bc-inner-blocks-right"[^>]*>"#, in: section)
            guard sides.count == 2, sides[0].contains("Покупка"), sides[1].contains("Продажа") else { continue }
            var banks: [String: (name: String, buy: Decimal?, sell: Decimal?)] = [:]
            for (side, text) in sides.enumerated() {
                for entry in split(#"<div\s+class="bc-inner-block-left-texts"#, in: text).dropFirst() {
                    guard let name = matches(#"<a href="/currency/bank/([a-z0-9-]+)">\s*<span[^>]*>\s*([^<]+?)\s*</span>\s*</a>"#, entry).first,
                          let value = matches(#"</a>\s*</div>\s*<span[^>]*>\s*([0-9][0-9\s.,&;]*)\s*сум\s*</span>"#, entry).first,
                          let rate = Money.parse(clean(value[1])), rate > 0 else { continue }
                    let id = bankID(name[1]); var item = banks[id] ?? (clean(name[2]), nil, nil)
                    if side == 0 { item.buy = rate } else { item.sell = rate }; banks[id] = item
                }
            }
            for (id, item) in banks {
                result.append(BankQuote(bankID: id, bankName: item.name, currency: currency, channel: .cash, buy: item.buy, sell: item.sell, provider: "bankuz", sourceURL: sources[2].url, publishedAt: nil, observedAt: now))
            }
        }
        return result
    }
}
