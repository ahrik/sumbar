import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case ru, uz
    var id: String { rawValue }
    var title: String { self == .ru ? "Русский" : "O‘zbekcha" }
}

/// Keeps interpolated values separate from the translated format; never translates bank IDs or ticker symbols.
struct LocalizedMessage: ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
    let key: String
    let arguments: [String]
    init(stringLiteral value: String) { key = value; arguments = [] }
    init(stringInterpolation: StringInterpolation) { key = stringInterpolation.key; arguments = stringInterpolation.arguments }
    struct StringInterpolation: StringInterpolationProtocol {
        var key = ""
        var arguments: [String] = []
        init(literalCapacity: Int, interpolationCount: Int) { key.reserveCapacity(literalCapacity) }
        mutating func appendLiteral(_ literal: String) { key += literal.replacingOccurrences(of: "%", with: "%%") }
        mutating func appendInterpolation<T>(_ value: T) { key += "%@"; arguments.append(String(describing: value)) }
    }
}
struct L10n {
    let language: AppLanguage
    private static let bundles: [String: Bundle] = Dictionary(uniqueKeysWithValues: AppLanguage.allCases.map { language in
        (language.rawValue, Bundle.module.path(forResource: language.rawValue, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .module)
    })
    private var bundle: Bundle {
        Self.bundles[language.rawValue] ?? .module
    }
    func literal(_ key: String) -> String { bundle.localizedString(forKey: key, value: key, table: "Localizable") }
    func callAsFunction(_ message: LocalizedMessage) -> String {
        let format = literal(message.key)
        guard !message.arguments.isEmpty else { return format }
        return String(format: format, locale: Locale(identifier: language.rawValue), arguments: message.arguments.map { $0 as CVarArg })
    }
    func status(_ status: DataStatus) -> String {
        if status.error != nil { return self("Не удалось обновить · сохранённые данные") }
        guard let date = status.checkedAt else { return self("Ожидание данных") }
        return self("\(status.isCurrent ? self("Проверено") : self("Проверка устарела")) \(Dates.display(date))")
    }
    func error(_ error: Error) -> String {
        if let error = error as? CBUConnectionError {
            switch error {
            case .certificate: return self("Не удалось проверить HTTPS-сертификат ЦБ. Повторите обновление позже или проверьте VPN и сеть.")
            case .tls: return self("Не удалось установить защищённое соединение с ЦБ. Повторите обновление позже или проверьте VPN и сеть.")
            }
        }
        if let error = error as? MarketError {
            switch error {
            case .invalidData: return self("Источник вернул данные неизвестного формата.")
            case .http(let code): return self("Источник временно недоступен (HTTP \(code)).")
            }
        }
        if let error = error as? RequestError {
            switch error {
            case .limited(let code, let date): return self("Источник временно ограничил запросы (HTTP \(code)). Следующая попытка после \(Dates.display(date)), Ташкент.")
            case .backoff(let date): return self("Источник просит подождать до \(Dates.display(date)), Ташкент. Сохранённые данные остаются доступны.")
            }
        }
        if error is NotificationError { return self("Уведомления не разрешены в настройках macOS.") }
        return error.localizedDescription
    }
}
