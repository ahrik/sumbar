import Foundation

extension BankProviders {
    /// Matches the official site's destination and minor-unit mapping. Unknown
    /// channels and amount-conditioned rows never become general offers.
    static func decodeHamkor(_ data: Data, at now: Date) throws -> [BankQuote] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["status"] as? String == "Success", Providers.decimal(object["error_code"]) == 0,
              let rows = object["data"] as? [[String: Any]] else { throw MarketError.invalidData }
        let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let standard = ISO8601DateFormatter()
        func date(_ raw: Any?) -> Date? {
            guard let raw = raw as? String else { return nil }
            return fractional.date(from: raw) ?? standard.date(from: raw)
        }
        func price(_ raw: Any?) -> Decimal? { Providers.decimal(raw).flatMap { $0 > 0 ? $0 / 100 : nil } }
        return rows.compactMap { row in
            guard let code = row["currency_char"] as? String, ["USD", "EUR", "RUB", "JPY", "CHF", "GBP"].contains(code),
                  Providers.decimal(row["begin_sum_i"]) == 0,
                  let destination = Providers.decimal(row["destination_code"]), destination == 2 || destination == 7,
                  let created = date(row["created_at"]), let effective = date(row["begin_date"]), effective <= now else { return nil }
            let buy = price(row["buying_rate"]); let sell = price(row["selling_rate"])
            guard buy != nil || sell != nil else { return nil }
            return BankQuote(bankID: "hamkorbank", bankName: "Hamkorbank", currency: code, channel: destination == 7 ? .app : .cash, buy: buy, sell: sell, provider: "hamkor", sourceURL: "https://hamkorbank.uz/exchange-rate/", publishedAt: max(created, effective), observedAt: now)
        }
    }
}
