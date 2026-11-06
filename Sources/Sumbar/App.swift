import AppKit
import SwiftUI
import Observation

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = MarketStore()
    let desktop = DesktopControls()
    let notifications = LocalNotifications()
    var statusItem: NSStatusItem!
    let popover = NSPopover()
    var wakeObserver: NSObjectProtocol?
    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "chart.xyaxis.line", accessibilityDescription: store.l10n("Sumbar — финансы Узбекистана"))
            button.target = self; button.action = #selector(togglePanel)
        }
        let height = min(CGFloat(760), (NSScreen.main?.visibleFrame.height ?? 820) - 40)
        popover.contentSize = NSSize(width: 520, height: height)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: PanelView(store: store, panelHeight: height, desktop: desktop, notifications: notifications))
        desktop.togglePanel = { [weak self] in self?.togglePanel() }
        desktop.refreshLoginStatus()
        notifications.onOpen = { [weak self] id in
            self?.store.openAlert(id)
            self?.showPanel(followPin: false)
        }
        store.alerts.sender = { [weak notifications] event, rule in
            guard let notifications else { throw NotificationError.notAuthorized }
            try await notifications.send(event, rule: rule)
        }
        store.alerts.onRemove = { [weak notifications] id in notifications?.remove(id) }
        Task {
            await notifications.connect()
            store.alerts.canDeliver = notifications.authorized
            await store.evaluateAlerts()
        }
        observeStatusItem()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.store.refresh(force: false) }
        }
        store.start()
        if CommandLine.arguments.contains("--preview") { togglePanel() }
    }
    func applicationWillTerminate(_ notification: Notification) { store.stop(); desktop.stop() }
    private func observeStatusItem() {
        withObservationTracking {
            let quote = store.menuBarQuote()
            statusItem.button?.title = quote.title
            statusItem.button?.toolTip = quote.tooltip
            statusItem.button?.setAccessibilityLabel(quote.tooltip)
            statusItem.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            statusItem.button?.imagePosition = quote.title.isEmpty ? .imageOnly : .imageLeading
            desktop.configureShortcut(store.preferences.shortcut)
            if desktop.language != store.language { desktop.language = store.language }
            if notifications.language != store.language { notifications.language = store.language }
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeStatusItem() }
        }
    }
    @objc func togglePanel() {
        if popover.isShown { popover.performClose(nil) }
        else { showPanel(followPin: true) }
    }
    private func showPanel(followPin: Bool) {
        guard let button = statusItem.button else { return }
        store.now = Date()
        if followPin { store.openPinnedQuote() }
        desktop.refreshLoginStatus()
        if !popover.isShown { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY) }
        popover.contentViewController?.view.window?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
        Task {
            await notifications.refreshAuthorization()
            store.alerts.canDeliver = notifications.authorized
            await store.refresh(force: false)
        }
    }
}
@main enum SumbarMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        #if DEBUG
        if let index = CommandLine.arguments.firstIndex(of: "--render-design"), CommandLine.arguments.count > index + 1 {
            do { try DesignPreview.render(to: URL(fileURLWithPath: CommandLine.arguments[index + 1])) }
            catch { FileHandle.standardError.write(Data("Design render failed: \(error)\n".utf8)); exit(1) }
            return
        }
        #endif
        let delegate = AppDelegate(); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
