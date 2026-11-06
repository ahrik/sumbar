import SwiftUI

struct OverviewSettingsView: View {
    @Bindable var store: MarketStore
    var desktop: DesktopControls?
    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 14) {
                Label("Строка меню", systemImage: "menubar.rectangle").font(.system(size: 13, weight: .semibold))
                Picker("Показывать", selection: $store.preferences.menuMode) {
                    ForEach(MenuBarMode.allCases) { Text($0.title).tag($0) }
                }
                if store.preferences.menuMode == .cbu || store.preferences.menuMode == .bank {
                    Picker("Валюта", selection: $store.preferences.menuCurrency) {
                        ForEach(Array(Set(store.cache.currencies.map(\.code) + [store.preferences.menuCurrency])).sorted(), id: \.self) { Text($0).tag($0) }
                    }
                }
                if store.preferences.menuMode == .bank {
                    Picker("Банк", selection: $store.preferences.menuBankID) {
                        Text("Выберите банк").tag(Optional<String>.none)
                        if let id = store.preferences.menuBankID, !store.bankChoices.contains(where: { $0.bankID == id }) {
                            Text("\(id) — недоступен").tag(Optional(id))
                        }
                        ForEach(store.bankChoices, id: \.bankID) { Text($0.bankName).tag(Optional($0.bankID)) }
                    }
                    Picker("Операция", selection: $store.preferences.menuBankAction) {
                        Text("Покупаю валюту").tag(ExchangeAction.buy)
                        Text("Продаю валюту").tag(ExchangeAction.sell)
                    }
                    Picker("Способ обмена", selection: $store.preferences.menuBankChannel) {
                        ForEach(BankChannel.allCases) { Text($0.title).tag($0) }
                    }
                }
                if store.preferences.menuMode == .security {
                    Picker("Бумага", selection: $store.preferences.menuInstrumentID) {
                        Text("Выберите бумагу").tag(Optional<String>.none)
                        if let id = store.preferences.menuInstrumentID, !store.cache.instruments.contains(where: { $0.id == id }) {
                            Text("\(id) — недоступна").tag(Optional(id))
                        }
                        ForEach(store.cache.instruments) { Text("\($0.ticker) · \($0.name)").tag(Optional($0.id)) }
                    }
                }
                Text(store.menuBarQuote().title.isEmpty ? "В строке меню будет только иконка Sumbar." : store.menuBarQuote().title)
                    .font(.system(size: 12, weight: .medium)).monospacedDigit()
                Text("При устаревшей проверке показываем прочерк. Дата действия курса, торговая сессия и источник — в подсказке при наведении.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        Surface {
            VStack(alignment: .leading, spacing: 14) {
                Label("Быстрый доступ", systemImage: "keyboard").font(.system(size: 13, weight: .semibold))
                Picker("Открыть Sumbar откуда угодно", selection: $store.preferences.shortcut) {
                    ForEach(PanelShortcut.allCases) { Text($0.title).tag($0) }
                }
                if let desktop {
                    Toggle("Открывать при входе в macOS", isOn: Binding(get: { desktop.loginEnabled || desktop.loginNeedsApproval }, set: { enabled in Task { await desktop.setLoginEnabled(enabled) } }))
                        .disabled(!desktop.canConfigureLogin)
                    if !desktop.canConfigureLogin { Text("Автозапуск доступен в собранном Sumbar.app.").font(.system(size: 11)).foregroundStyle(.secondary) }
                    if desktop.loginNeedsApproval {
                        Button("Разрешить автозапуск в настройках macOS") { desktop.openLoginSettings() }
                    }
                    if let error = desktop.loginError { Text(error).foregroundStyle(.orange).font(.system(size: 11)) }
                    if let error = desktop.shortcutError { Text(error).foregroundStyle(.orange).font(.system(size: 11)) }
                }
                Text("Звезда добавляет валюту, банк или бумагу в избранное. Значок закрепления выбирает показатель для строки меню.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        if !store.preferences.favoriteCurrencies.isEmpty || !store.preferences.favoriteBanks.isEmpty || !store.preferences.favoriteInstruments.isEmpty {
            DisclosureGroup("Управление избранным") {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(store.preferences.favoriteCurrencies, id: \.self) { code in
                        favoriteRow(code) { store.toggleCurrencyFavorite(code) }
                    }
                    ForEach(store.preferences.favoriteBanks, id: \.self) { id in
                        favoriteRow(store.bankChoices.first { $0.bankID == id }?.bankName ?? "\(id) — недоступен") { store.toggleBankFavorite(id) }
                    }
                    ForEach(store.preferences.favoriteInstruments, id: \.self) { id in
                        favoriteRow(store.cache.instruments.first { $0.id == id }?.ticker ?? "\(id) — недоступна") { store.toggleInstrumentFavorite(id) }
                    }
                }.padding(.top, 8)
            }.font(.system(size: 12))
        }
    }
    private func favoriteRow(_ title: String, remove: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
            Spacer()
            Button(action: remove) { Image(systemName: "star.slash") }.buttonStyle(.borderless).accessibilityLabel("Удалить \(title) из избранного")
        }
    }
}
