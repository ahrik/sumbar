import Foundation

struct Instrument: Codable, Identifiable, Hashable, Sendable {
    let key: String; let ticker: String; let name: String; let kind: String; let currency: String
    let price: Decimal?; let changePercent: Decimal?; let tradeDate: String?
    var id: String { kind + ":" + key }
}
struct SecurityDetail: Codable, Sendable {
    let history: [PricePoint]
    let coupon: Decimal?
    let faceValue: Decimal?
    var session: SecuritySession? = nil
    var couponFrequency: Int? = nil
    var issueDate: String? = nil
    var maturityDate: String? = nil
    var issuerName: String? = nil
    var sector: String? = nil
    var priceBasis: String? = nil
    var disclosures: [IssuerDisclosure]? = nil
    func unitPrice(_ raw: Decimal?, kind: String) -> Decimal? {
        guard let raw, raw > 0 else { return nil }
        if kind == "stock" || priceBasis == "amount_per_bond" { return raw }
        if priceBasis == "percent_of_par", let faceValue, faceValue > 0 { return raw * faceValue / 100 }
        return nil
    }
}
struct SecuritySession: Codable, Sendable {
    let date: String?
    let open: Decimal?
    let high: Decimal?
    let low: Decimal?
    let volume: Decimal?
    let turnover: Decimal?
    let volumeUnit: String?
}
struct IssuerDisclosure: Codable, Identifiable, Sendable {
    let title: String
    let date: String?
    let url: URL
    var id: String { url.absoluteString + ":" + (date ?? "") + ":" + title }
}
struct CacheState: Codable {
    var currencies: [CurrencyQuote] = []
    var bankQuotes: [BankQuote]?
    var instruments: [Instrument] = []
    var observed: [String: [PricePoint]] = [:]
    var currencyHistory: [String: [PricePoint]] = [:]
    var currencyHistoryDay: String?
    var details: [String: SecurityDetail] = [:]
    var fxChecked: Date?
    var stocksChecked: Date?
}
