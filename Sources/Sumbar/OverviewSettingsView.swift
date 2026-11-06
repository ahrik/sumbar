import SwiftUI

struct OverviewSettingsView: View {
    @Bindable var store: MarketStore
    var desktop: DesktopControls?
    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 14) {
                Label(store.l10n("Строка меню"), systemImage: "menubar.rectangle").font(.system(size: 13, weight: .semibold))
                Picker(store.l10n("Показывать"), selection: $store.preferences.menuMode) {
                    ForEach(MenuBarMode.allCases) { Text(store.l10n.literal($0.title)).tag($0) }
                }
                if store.preferences.menuMode == .cbu || store.preferences.menuMode == .bank {
                    Picker(store.l10n("Валюта"), selection: $store.preferences.menuCurrency) {
                        ForEach(Array(Set(store.cache.currencies.map(\.code) + [store.preferences.menuCurrency])).sorted(), id: \.self) { Text($0).tag($0) }
                    }
                }
                if store.preferences.menuMode == .bank {
                    Picker(store.l10n("Банк"), selection: $store.preferences.menuBankID) {
                        Text(store.l10n("Выберите банк")).tag(Optional<String>.none)
                        if let id = store.preferences.menuBankID, !store.bankChoices.contains(where: { $0.bankID == id }) {
                            Text(store.l10n("\(id) — недоступен")).tag(Optional(id))
                        }
                        ForEach(store.bankChoices, id: \.bankID) { Text($0.bankName).tag(Optional($0.bankID)) }
                    }
                    Picker(store.l10n("Операция"), selection: $store.preferences.menuBankAction) {
                        Text(store.l10n("Покупаю валюту")).tag(ExchangeAction.buy)
                        Text(store.l10n("Продаю валюту")).tag(ExchangeAction.sell)
                    }
                    Picker(store.l10n("Способ обмена"), selection: $store.preferences.menuBankChannel) {
                        ForEach(BankChannel.allCases) { Text(store.l10n.literal($0.title)).tag($0) }
                    }
                }
                if store.preferences.menuMode == .security {
                    Picker(store.l10n("Бумага"), selection: $store.preferences.menuInstrumentID) {
                        Text(store.l10n("Выберите бумагу")).tag(Optional<String>.none)
                        if let id = store.preferences.menuInstrumentID, !store.cache.instruments.contains(where: { $0.id == id }) {
                            Text(store.l10n("\(id) — недоступна")).tag(Optional(id))
                        }
                        ForEach(store.cache.instruments) { Text("\($0.ticker) · \($0.name)").tag(Optional($0.id)) }
                    }
                }
                Text(store.menuBarQuote().title.isEmpty ? store.l10n("В строке меню будет только иконка Sumbar.") : store.menuBarQuote().title)
                    .font(.system(size: 12, weight: .medium)).monospacedDigit()
                Text(store.l10n("При устаревшей проверке показываем прочерк. Дата действия курса, торговая сессия и источник — в подсказке при наведении."))
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        Surface {
            VStack(alignment: .leading, spacing: 14) {
                Label(store.l10n("Быстрый доступ"), systemImage: "keyboard").font(.system(size: 13, weight: .semibold))
                Picker(store.l10n("Открыть Sumbar откуда угодно"), selection: $store.preferences.shortcut) {
                    ForEach(PanelShortcut.allCases) { Text(store.l10n.literal($0.title)).tag($0) }
                }
                if let desktop {
                    Toggle(store.l10n("Открывать при входе в macOS"), isOn: Binding(get: { desktop.loginEnabled || desktop.loginNeedsApproval }, set: { enabled in Task { await desktop.setLoginEnabled(enabled) } }))
                        .disabled(!desktop.canConfigureLogin)
                    if !desktop.canConfigureLogin { Text(store.l10n("Автозапуск доступен в собранном Sumbar.app.")).font(.system(size: 11)).foregroundStyle(.secondary) }
                    if desktop.loginNeedsApproval {
                        Button(store.l10n("Разрешить автозапуск в настройках macOS")) { desktop.openLoginSettings() }
                    }
                    if let error = desktop.loginError { Text(error).foregroundStyle(.orange).font(.system(size: 11)) }
                    if let error = desktop.shortcutError { Text(error).foregroundStyle(.orange).font(.system(size: 11)) }
                }
                Text(store.l10n("Звезда добавляет валюту, банк или бумагу в избранное. Значок закрепления выбирает показатель для строки меню."))
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        Surface {
            VStack(alignment: .leading, spacing: 10) {
                Label(store.l10n("Виджеты macOS"), systemImage: "rectangle.grid.2x2")
                    .font(.system(size: 13, weight: .semibold))
                Text(store.l10n("Нажмите дату и время в строке меню → «Изменить виджеты» → Sumbar. Или нажмите правой кнопкой на рабочем столе → «Изменить виджеты»."))
                    .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                Text(store.l10n("Доступны курс одной валюты и список курсов ЦБ. Размер, валюту и язык можно выбрать в меню виджета. Нажатие на курс открывает его в Sumbar."))
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text(store.l10n("Виджеты обновляются по расписанию macOS независимо от приложения. При сбое сети показаны сохранённые данные с датой проверки."))
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if Bundle.main.bundleURL.pathExtension != "app" {
                    Text(store.l10n("Виджеты доступны после установки собранного Sumbar.app в «Программы» и первого запуска."))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
        if !store.preferences.favoriteCurrencies.isEmpty || !store.preferences.favoriteBanks.isEmpty || !store.preferences.favoriteInstruments.isEmpty {
            DisclosureGroup(store.l10n("Управление избранным")) {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(store.preferences.favoriteCurrencies, id: \.self) { code in
                        favoriteRow(code) { store.toggleCurrencyFavorite(code) }
                    }
                    ForEach(store.preferences.favoriteBanks, id: \.self) { id in
                        favoriteRow(store.bankChoices.first { $0.bankID == id }?.bankName ?? store.l10n("\(id) — недоступен")) { store.toggleBankFavorite(id) }
                    }
                    ForEach(store.preferences.favoriteInstruments, id: \.self) { id in
                        favoriteRow(store.cache.instruments.first { $0.id == id }?.ticker ?? store.l10n("\(id) — недоступна")) { store.toggleInstrumentFavorite(id) }
                    }
                }.padding(.top, 8)
            }.font(.system(size: 12))
        }
    }
    private func favoriteRow(_ title: String, remove: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
            Spacer()
            Button(action: remove) { Image(systemName: "star.slash") }.buttonStyle(.borderless).accessibilityLabel(store.l10n("Удалить \(title) из избранного"))
        }
    }
}
