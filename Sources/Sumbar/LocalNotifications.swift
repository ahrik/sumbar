import AppKit
import UserNotifications
import Observation

@MainActor @Observable final class LocalNotifications: NSObject, UNUserNotificationCenterDelegate {
    var authorized = false
    var language = AppLanguage.ru
    private var tr: L10n { L10n(language: language) }
    var error: String?
    var onOpen: ((UUID) -> Void)?
    var supported: Bool { Bundle.main.bundleURL.pathExtension == "app" }
    private var center: UNUserNotificationCenter { UNUserNotificationCenter.current() }

    func connect() async {
        guard supported else { return }
        center.delegate = self
        await refreshAuthorization()
    }
    func refreshAuthorization() async {
        guard supported else { return }
        let settings = await center.notificationSettings()
        authorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }
    func requestPermission() async -> Bool {
        error = nil
        guard supported else { error = tr("Уведомления доступны в собранном Sumbar.app."); return false }
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
            await refreshAuthorization()
            if !authorized { error = tr("Разрешите уведомления Sumbar в настройках macOS.") }
        } catch { self.error = tr("Не удалось запросить уведомления: \(tr.error(error))") }
        return authorized
    }
    func send(_ event: RateAlertEvent, rule: RateAlertRule) async throws {
        await refreshAuthorization()
        guard authorized else { throw NotificationError.notAuthorized }
        let delivered = await center.deliveredNotifications()
        let pending = await center.pendingNotificationRequests()
        guard !delivered.contains(where: { $0.request.identifier == event.notificationID }), !pending.contains(where: { $0.identifier == event.notificationID }) else { return }
        let content = UNMutableNotificationContent()
        content.title = tr("\(rule.currency): нужный курс достигнут")
        let kind = rule.source == .cbu ? tr("Курс ЦБ") : "\(rule.action == .buy ? tr("Покупка") : tr("Продажа")) · \(tr.literal(rule.channel.title))"
        content.body = tr("\(kind): \(Money.format(event.observation.value)) UZS\n\(tr.literal(event.observation.sourceName))\nПубликация \(event.observation.publication) · проверено \(Dates.display(event.observation.checkedAt)), Ташкент")
        content.sound = .default
        content.userInfo = ["ruleID": rule.id.uuidString]
        try await center.add(UNNotificationRequest(identifier: event.notificationID, content: content, trigger: nil))
    }
    func test() async {
        guard await requestPermission() else { return }
        let content = UNMutableNotificationContent()
        content.title = tr("Sumbar: проверка уведомлений")
        content.body = tr("Уведомления работают. Курсы проверяются, пока Sumbar запущен и Mac не спит.")
        content.sound = .default
        do { try await center.add(UNNotificationRequest(identifier: "sumbar.test", content: content, trigger: nil)) }
        catch { self.error = tr("Не удалось отправить проверку: \(tr.error(error))") }
    }
    func remove(_ identifier: String) {
        guard supported else { return }
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }
    func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(url) }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .sound] }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let value = response.notification.request.content.userInfo["ruleID"] as? String, let id = UUID(uuidString: value) else { return }
        await MainActor.run { self.onOpen?(id) }
    }
}
enum NotificationError: LocalizedError {
    case notAuthorized
    var errorDescription: String? { "Уведомления не разрешены в настройках macOS." }
}
