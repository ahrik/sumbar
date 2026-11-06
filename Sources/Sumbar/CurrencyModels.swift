import Foundation

enum MarketError: LocalizedError {
    case invalidData, http(Int)
    var errorDescription: String? {
        switch self {
        case .invalidData: return "Источник вернул данные неизвестного формата."
        case .http(let code): return "Источник временно недоступен (HTTP \(code))."
        }
    }
}
enum Money {
    static let locale = Locale(identifier: "en_US_POSIX")
    static func parse(_ text: String) -> Decimal? {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\u{00a0}", with: "").replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ",", with: ".")
        guard s.range(of: #"^[+-]?[0-9]+(\.[0-9]+)?$"#, options: .regularExpression) != nil else { return nil }
        return Decimal(string: s, locale: locale)
    }
    static func format(_ value: Decimal?, digits: Int = 2) -> String {
        guard let value else { return "—" }
        let f = NumberFormatter(); f.locale = Locale(identifier: "ru_RU"); f.numberStyle = .decimal
        f.maximumFractionDigits = digits; f.minimumFractionDigits = 0
        return f.string(from: NSDecimalNumber(decimal: value)) ?? "—"
    }
    static func investment(quantity: Decimal, entry: Decimal, exit: Decimal, fee: Decimal) -> (cost: Decimal, proceeds: Decimal, profit: Decimal) {
        let cost = quantity * entry * (1 + fee / 100)
        let proceeds = quantity * exit * (1 - fee / 100)
        return (cost, proceeds, proceeds - cost)
    }
}
enum Dates {
    static var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Tashkent")!; return c }
    static func formatter(_ pattern: String) -> DateFormatter {
        let f = DateFormatter(); f.locale = Money.locale; f.calendar = calendar; f.timeZone = calendar.timeZone; f.dateFormat = pattern; return f
    }
    static func day(_ date: Date = Date()) -> String { formatter("yyyy-MM-dd").string(from: date) }
    static func parse(_ string: String, pattern: String = "yyyy-MM-dd") -> Date? { formatter(pattern).date(from: string) }
    static func display(_ date: Date) -> String { formatter("dd.MM HH:mm").string(from: date) }
}
struct PricePoint: Codable, Identifiable, Sendable {
    var date: Date
    var price: Decimal
    var id: Date { date }
    var value: Double { NSDecimalNumber(decimal: price).doubleValue }
}
struct CurrencyQuote: Codable, Identifiable, Equatable, Sendable {
    let code: String; let name: String; let price: Decimal; let change: Decimal; let effectiveDate: String
    var nameUz: String? = nil
    var id: String { code }
}
struct CBURecord: Decodable, Sendable {
    let Ccy: String; let CcyNm_RU: String; let Nominal: String; let Rate: String; let Diff: String; let Date: String
    var CcyNm_UZ: String? = nil
    func quote() throws -> CurrencyQuote {
        guard let nominal = Money.parse(Nominal), nominal > 0, let rate = Money.parse(Rate), rate > 0, let diff = Money.parse(Diff), Dates.parse(Date, pattern: "dd.MM.yyyy") != nil else { throw MarketError.invalidData }
        return CurrencyQuote(code: Ccy, name: CcyNm_RU, price: rate / nominal, change: diff / nominal, effectiveDate: Date, nameUz: CcyNm_UZ)
    }
}
