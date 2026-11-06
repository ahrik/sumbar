import AppKit
import Carbon
import ServiceManagement
import Observation

@MainActor @Observable final class DesktopControls {
    var loginEnabled = false
    var language = AppLanguage.ru
    private var tr: L10n { L10n(language: language) }
    var loginNeedsApproval = false
    var loginError: String?
    var shortcutError: String?
    var togglePanel: (() -> Void)?
    var togglePanelPin: (() -> Void)?
    var hidePanel: (() -> Void)?
    var panelPinned = false
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var registeredShortcut: PanelShortcut?
    var canConfigureLogin: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    func refreshLoginStatus() {
        guard canConfigureLogin else { return }
        loginEnabled = SMAppService.mainApp.status == .enabled
        loginNeedsApproval = SMAppService.mainApp.status == .requiresApproval
    }
    func setLoginEnabled(_ enabled: Bool) async {
        loginError = nil
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try await SMAppService.mainApp.unregister() }
        } catch { loginError = tr("Не удалось изменить автозапуск: \(tr.error(error))") }
        refreshLoginStatus()
    }
    func openLoginSettings() { SMAppService.openSystemSettingsLoginItems() }

    func configureShortcut(_ shortcut: PanelShortcut) {
        guard registeredShortcut != shortcut else { return }
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
        registeredShortcut = shortcut; shortcutError = nil
        guard shortcut != .off else { return }
        if handler == nil {
            var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
                guard let context else { return OSStatus(eventNotHandledErr) }
                MainActor.assumeIsolated {
                    Unmanaged<DesktopControls>.fromOpaque(context).takeUnretainedValue().togglePanel?()
                }
                return noErr
            }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
            guard status == noErr else { shortcutError = tr("Не удалось включить глобальную клавишу."); return }
        }
        let modifiers: UInt32
        switch shortcut {
        case .optionCommandS: modifiers = UInt32(optionKey | cmdKey)
        case .controlOptionS: modifiers = UInt32(controlKey | optionKey)
        case .shiftCommandS: modifiers = UInt32(shiftKey | cmdKey)
        case .off: return
        }
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_S), modifiers, EventHotKeyID(signature: 0x53554D42, id: 1), GetApplicationEventTarget(), 0, &hotKey)
        if status != noErr { shortcutError = tr("Клавиша \(shortcut.title) недоступна. Выберите другое сочетание.") }
    }
    func stop() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil; handler = nil
    }
}
