import SwiftUI

struct AlertsView: View {
    @Bindable var store: MarketStore
    var notifications: LocalNotifications?
    @State private var adding = false
    private var sample: AlertObservation? {
        var draft = store.alerts.draft
        if draft.rule() == nil { draft.threshold = "1" }
        guard let rule = draft.rule() else { return nil }
        return AlertObservation.lookup(rule, cache: store.cache, fxError: store.fxError, bankErrors: Set(store.bankErrors.keys), refreshMinutes: store.refreshMinutes, now: store.now)
    }
    var body: some View {
        @Bindable var alerts = store.alerts
        return VStack(alignment: .leading, spacing: 18) {
            Text(store.l10n("Уведомления о курсе")).font(.system(size: 20, weight: .semibold))
            Text(store.l10n("Одно правило — один сигнал. Новая проверка раз в \(store.refreshMinutes) минут; во сне и после выхода из Sumbar проверок нет."))
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Surface {
                VStack(alignment: .leading, spacing: 13) {
                    Label(store.l10n("Новое правило"), systemImage: "bell.badge").font(.system(size: 13, weight: .semibold))
                    Picker(store.l10n("Источник"), selection: $alerts.draft.source) {
                        ForEach(AlertSource.allCases) { Text(store.l10n.literal($0.title)).tag($0) }
                    }
                    Picker(store.l10n("Валюта"), selection: $alerts.draft.currency) {
                        ForEach(Array(Set(store.cache.currencies.map(\.code) + [store.alerts.draft.currency])).sorted(), id: \.self) { Text($0).tag($0) }
                    }
                    if store.alerts.draft.source == .bank {
                        Picker(store.l10n("Банк"), selection: $alerts.draft.bankID) {
                            Text(store.l10n("Выберите банк")).tag(Optional<String>.none)
                            if let id = alerts.draft.bankID, !store.bankChoices.contains(where: { $0.bankID == id }) {
                                Text(store.l10n("\(id) — недоступен")).tag(Optional(id))
                            }
                            ForEach(store.bankChoices, id: \.bankID) { Text($0.bankName).tag(Optional($0.bankID)) }
                        }
                        Picker(store.l10n("Операция"), selection: $alerts.draft.action) {
                            Text(store.l10n("Покупаю валюту")).tag(ExchangeAction.buy)
                            Text(store.l10n("Продаю валюту")).tag(ExchangeAction.sell)
                        }
                        Picker(store.l10n("Способ обмена"), selection: $alerts.draft.channel) {
                            ForEach(BankChannel.allCases) { Text(store.l10n.literal($0.title)).tag($0) }
                        }
                    }
                    HStack {
                        Picker(store.l10n("Условие"), selection: $alerts.draft.comparison) {
                            ForEach(AlertComparison.allCases) { Text(store.l10n.literal($0.title)).tag($0) }
                        }
                        TextField(store.l10n("Курс в UZS"), text: $alerts.draft.threshold).textFieldStyle(.roundedBorder)
                            .accessibilityLabel(store.l10n("Целевой курс в UZS за единицу валюты"))
                    }
                    if let sample {
                        Text(store.l10n("Сейчас: \(Money.format(sample.value)) UZS · публикация \(sample.publication)"))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        if let rule = store.alerts.draft.rule(), rule.comparison.matches(sample.value, threshold: rule.threshold) {
                            Text(store.l10n("Условие уже выполнено.")).font(.system(size: 11, weight: .medium))
                        }
                    } else {
                        Text(store.l10n("Для оценки нужен положительный порог и свежий курс. Банковский сигнал требует известного времени публикации."))
                            .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Toggle(store.l10n("Уведомить и при первом совпадении"), isOn: $alerts.draft.notifyOnFirstMatch).toggleStyle(.checkbox)
                    Text(store.l10n("Если выключено, сначала ждём значение за пределами условия, затем его пересечение. Пропущенные во сне колебания не восстанавливаются."))
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button(adding ? store.l10n("Добавляем…") : store.l10n("Добавить уведомление")) { Task { await add() } }
                        .buttonStyle(.borderedProminent).disabled(adding || store.alerts.draft.rule() == nil || notifications?.supported != true)
                }.font(.system(size: 12))
            }
            if let notifications {
                HStack {
                    Text(notifications.authorized ? store.l10n("Уведомления macOS разрешены") : store.l10n("Для сигналов нужно разрешение macOS")).font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Button(store.l10n("Проверить")) { Task { await notifications.test(); store.alerts.canDeliver = notifications.authorized } }.buttonStyle(.borderless)
                    Button(store.l10n("Настройки macOS")) { notifications.openSettings() }.buttonStyle(.borderless)
                }.font(.system(size: 11))
                if !notifications.supported { Text(store.l10n("Уведомления доступны в собранном Sumbar.app.")).font(.system(size: 11)).foregroundStyle(.secondary) }
                if let error = notifications.error { Text(error).font(.system(size: 11)).foregroundStyle(.orange) }
            }
            if let error = store.alerts.error { Text(error).font(.system(size: 11)).foregroundStyle(.orange) }
            Text(store.l10n("Ваши правила: \(store.alerts.rules.count)")).font(.system(size: 13, weight: .semibold))
            if store.alerts.rules.isEmpty { Text(store.l10n("Добавьте первое правило выше.")).font(.system(size: 12)).foregroundStyle(.secondary) }
            ForEach(store.alerts.rules) { rule in
                Surface {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("\(rule.currency) \(rule.comparison == .atOrAbove ? "≥" : "≤") \(Money.format(rule.threshold)) UZS").font(.system(size: 14, weight: .semibold)).monospacedDigit()
                            Spacer()
                            Text(rule.state == .active ? store.l10n("Активно") : rule.state == .paused ? store.l10n("Пауза") : store.l10n("Сработало")).font(.system(size: 11))
                        }
                        Text(rule.source == .cbu ? store.l10n("Курс ЦБ") : "\(rule.bankName ?? rule.bankID ?? "—") · \(store.l10n.literal(rule.channel.title)) · \(rule.action == .buy ? store.l10n("покупаю") : store.l10n("продаю"))")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        if rule.state == .active, AlertObservation.lookup(rule, cache: store.cache, fxError: store.fxError, bankErrors: Set(store.bankErrors.keys), refreshMinutes: store.refreshMinutes, now: store.now) == nil {
                            Text(store.l10n("Ожидание данных")).font(.system(size: 11)).foregroundStyle(.orange)
                        }
                        if let event = rule.event {
                            Text("\(Money.format(event.observation.value)) UZS · \(Dates.display(event.createdAt)) · \(rule.delivery == .sent ? store.l10n("Передано macOS") : rule.delivery == .expired ? store.l10n("Сигнал устарел") : store.l10n("Не отправлено"))")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        HStack {
                            Button(store.l10n("Открыть курс")) { store.openAlert(rule.id) }.buttonStyle(.borderless)
                            if rule.state != .triggered {
                                Button(rule.state == .paused ? store.l10n("Возобновить") : store.l10n("Приостановить")) { store.alerts.setPaused(rule.id, paused: rule.state == .active) }.buttonStyle(.borderless)
                            } else if rule.delivery == .failed {
                                Button(store.l10n("Повторить отправку")) { Task { await store.alerts.deliver(rule.id) } }.buttonStyle(.borderless)
                            }
                            Spacer()
                            Button(store.l10n("Удалить"), role: .destructive) { store.alerts.remove(rule.id) }.buttonStyle(.borderless)
                        }.font(.system(size: 11))
                    }
                }
            }
        }.task { await notifications?.refreshAuthorization(); store.alerts.canDeliver = notifications?.authorized == true }
    }
    private func add() async {
        guard !adding, let notifications else { return }
        adding = true; defer { adding = false }
        guard await notifications.requestPermission() else { return }
        store.alerts.canDeliver = notifications.authorized
        let name = store.bankChoices.first { $0.bankID == store.alerts.draft.bankID }?.bankName
        if let rule = store.alerts.draft.rule(bankName: name), store.alerts.add(rule) { await store.evaluateAlerts() }
    }
}
