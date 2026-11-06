import Foundation

enum CBUConnectionError: LocalizedError {
    case certificate, tls
    var errorDescription: String? {
        switch self {
        case .certificate: "Не удалось проверить HTTPS-сертификат ЦБ. Повторите обновление позже или проверьте VPN и сеть."
        case .tls: "Не удалось установить защищённое соединение с ЦБ. Повторите обновление позже или проверьте VPN и сеть."
        }
    }
}

enum CBUProvider {
    /// Both hosts belong to the documented CBU service. Each request still uses
    /// URLSession's normal certificate and hostname verification.
    static func currencies(date: Date, fetch: @Sendable (URL) async throws -> Data) async throws -> [CurrencyQuote] {
        let hosts = ["cbu.uz", "www.cbu.uz"]
        for (index, host) in hosts.enumerated() {
            try Task.checkCancellation()
            // Preserve the exact requested Tashkent date when changing hosts.
            let url = URL(string: "https://\(host)/ru/arkhiv-kursov-valyut/json/all/\(Dates.day(date))/")!
            let data: Data
            do { data = try await fetch(url) }
            catch {
                try Task.checkCancellation()
                // HTTP limits, invalid responses and cancellations must never
                // cause another request through the alternate host.
                if index == 0, shouldTryAlternate(error) { continue }
                if isCertificateError(error) { throw CBUConnectionError.certificate }
                if (error as? URLError)?.code == .secureConnectionFailed { throw CBUConnectionError.tls }
                throw error
            }
            try Task.checkCancellation()
            let records = try JSONDecoder().decode([CBURecord].self, from: data)
            let quotes = try records.map { try $0.quote() }
            guard !quotes.isEmpty else { throw MarketError.invalidData }
            return quotes
        }
        throw MarketError.invalidData
    }

    private static func shouldTryAlternate(_ error: Error) -> Bool {
        guard let error = error as? URLError else { return false }
        if isCertificateError(error) { return true }
        return [.secureConnectionFailed, .cannotFindHost, .dnsLookupFailed, .cannotConnectToHost, .networkConnectionLost, .timedOut].contains(error.code)
    }
    private static func isCertificateError(_ error: Error) -> Bool {
        guard let error = error as? URLError else { return false }
        return [.serverCertificateHasBadDate, .serverCertificateUntrusted, .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid].contains(error.code)
    }
}
