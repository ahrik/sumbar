import Foundation

enum MenuBarMode: String, Codable, CaseIterable, Identifiable {
    case icon, cbu, bank, security
    var id: String { rawValue }
    var title: String {
        switch self {
        case .icon: "Только иконка"
        case .cbu: "Курс ЦБ"
        case .bank: "Курс моего банка"
        case .security: "Закрытие бумаги"
        }
    }
}

enum PanelShortcut: String, Codable, CaseIterable, Identifiable {
    case optionCommandS, controlOptionS, shiftCommandS, off
    var id: String { rawValue }
    var title: String {
        switch self {
        case .optionCommandS: "⌥⌘S"
        case .controlOptionS: "⌃⌥S"
        case .shiftCommandS: "⇧⌘S"
        case .off: "Выключено"
        }
    }
}

struct OverviewPreferences: Codable, Equatable {
    var selectedCurrency = "USD"
    var selectedInstrumentID: String?
    var refreshMinutes = 15
    var favoriteCurrencies = ["USD", "EUR", "RUB", "KZT"]
    var favoriteBanks: [String] = []
    var favoriteInstruments: [String] = []
    var bankChannel = BankChannel.cash
    var bankAction = ExchangeAction.buy
    var menuMode = MenuBarMode.cbu
    var menuCurrency = "USD"
    var menuBankID: String?
    var menuBankChannel = BankChannel.cash
    var menuBankAction = ExchangeAction.buy
    var menuInstrumentID: String?
    var shortcut = PanelShortcut.optionCommandS

    static func load(_ defaults: UserDefaults) -> Self {
        if let data = defaults.data(forKey: "overviewPreferences"), var saved = try? JSONDecoder().decode(Self.self, from: data) {
            if ![15, 30, 60].contains(saved.refreshMinutes) { saved.refreshMinutes = 15 }
            return saved
        }
        var result = Self()
        result.selectedCurrency = defaults.string(forKey: "currency") ?? "USD"
        result.menuCurrency = result.selectedCurrency
        let minutes = defaults.integer(forKey: "refreshMinutes")
        if [15, 30, 60].contains(minutes) { result.refreshMinutes = minutes }
        return result
    }
    func save(_ defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: "overviewPreferences") }
    }
}

struct DataStatus {
    let checkedAt: Date?
    let error: String?
    let now: Date
    let maximumAge: TimeInterval
    var isCurrent: Bool {
        guard error == nil, let checkedAt else { return false }
        return (-300...maximumAge).contains(now.timeIntervalSince(checkedAt))
    }
    var text: String {
        if error != nil { return "Не удалось обновить · сохранённые данные" }
        guard let checkedAt else { return "Ожидание данных" }
        return "\(isCurrent ? "Проверено" : "Проверка устарела") \(Dates.display(checkedAt))"
    }
}

struct MenuBarQuote: Equatable {
    let title: String
    let tooltip: String
}
