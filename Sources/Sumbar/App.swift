import AppKit
import SwiftUI
import Observation

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let store = MarketStore()
    let desktop = DesktopControls()
    let notifications = LocalNotifications()
    var statusItem: NSStatusItem!
    let popover = NSPopover()
    var wakeObserver: NSObjectProtocol?
    var pinnedPanel: NSPanel?
    var contentController: NSHostingController<AnyView>!
    var standardPopoverSize = NSSize(width: 520, height: 760)
    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "chart.xyaxis.line", accessibilityDescription: store.l10n("Sumbar — финансы Узбекистана"))
            button.target = self; button.action = #selector(togglePanel)
        }
        let height = min(CGFloat(760), (NSScreen.main?.visibleFrame.height ?? 820) - 40)
        popover.contentSize = NSSize(width: 520, height: height)
        standardPopoverSize = popover.contentSize
        popover.behavior = .transient
        contentController = NSHostingController(rootView: AnyView(GeometryReader { [store, desktop, notifications] geometry in
            PanelView(store: store, panelHeight: geometry.size.height, panelWidth: geometry.size.width, desktop: desktop, notifications: notifications)
        }))
        contentController.preferredContentSize = standardPopoverSize
        contentController.view.setFrameSize(standardPopoverSize)
        contentController.view.autoresizingMask = [.width, .height]
        popover.contentViewController = contentController
        popover.contentSize = standardPopoverSize
        desktop.togglePanel = { [weak self] in self?.togglePanel() }
        desktop.togglePanelPin = { [weak self] in self?.togglePanelPin() }
        desktop.hidePanel = { [weak self] in self?.popover.performClose(nil); self?.pinnedPanel?.orderOut(nil) }
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
        if CommandLine.arguments.contains("--preview") || CommandLine.arguments.contains("--pin-panel") {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(250))
                if CommandLine.arguments.contains("--pin-panel") { self.togglePanelPin() }
                else { self.showPanel(followPin: true) }
                try? await Task.sleep(for: .milliseconds(500))
                if CommandLine.arguments.contains("--check-layout") { self.checkLaunchLayout() }
            }
        }
    }
    func applicationWillTerminate(_ notification: Notification) { store.stop(); desktop.stop() }
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let code = urls.compactMap({ WidgetLink.currency(from: $0) }).first else { return }
        store.selectedCurrency = code
        store.panelTab = 0
        showPanel(followPin: false)
    }
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
            pinnedPanel?.title = store.l10n("Sumbar — закреплённая панель")
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeStatusItem() }
        }
    }
    @objc func togglePanel() {
        if desktop.panelPinned {
            if pinnedPanel?.isVisible == true { pinnedPanel?.orderOut(nil) }
            else { showPanel(followPin: true) }
            return
        }
        if popover.isShown { popover.performClose(nil) }
        else { showPanel(followPin: true) }
    }
    private func showPanel(followPin: Bool) {
        guard let button = statusItem.button else { return }
        store.now = Date()
        if followPin { store.openPinnedQuote() }
        desktop.refreshLoginStatus()
        NSApp.activate(ignoringOtherApps: true)
        if desktop.panelPinned { pinnedPanel?.makeKeyAndOrderFront(nil) }
        else if !popover.isShown { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY) }
        popover.contentViewController?.view.window?.makeKey()
        Task {
            await notifications.refreshAuthorization()
            store.alerts.canDeliver = notifications.authorized
            await store.refresh(force: false)
        }
    }
    private func togglePanelPin() {
        if desktop.panelPinned { restorePopover(show: true); return }
        let animates = popover.animates; popover.animates = false
        popover.performClose(nil)
        popover.animates = animates
        popover.contentViewController = nil
        if pinnedPanel == nil {
            let panel = NSPanel(contentRect: NSRect(origin: .zero, size: standardPopoverSize), styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
            panel.isFloatingPanel = true; panel.hidesOnDeactivate = false; panel.level = .floating
            panel.isReleasedWhenClosed = false; panel.delegate = self
            panel.contentMinSize = NSSize(width: 520, height: 500)
            panel.center(); pinnedPanel = panel
        }
        pinnedPanel?.title = store.l10n("Sumbar — закреплённая панель")
        pinnedPanel?.contentViewController = contentController
        desktop.panelPinned = true
        pinnedPanel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    private func restorePopover(show: Bool) {
        pinnedPanel?.orderOut(nil); pinnedPanel?.contentViewController = nil
        popover.contentViewController = contentController
        popover.contentSize = standardPopoverSize
        contentController.view.setFrameSize(standardPopoverSize)
        desktop.panelPinned = false
        if show { showPanel(followPin: false) }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { restorePopover(show: false); return false }
    private func checkLaunchLayout() {
        guard CommandLine.arguments.contains("--preview") else { return }
        contentController.view.layoutSubtreeIfNeeded()
        let size = contentController.view.bounds.size
        let visible = desktop.panelPinned ? pinnedPanel?.isVisible == true : popover.isShown
        guard visible, size.width >= 500, size.height >= 400 else {
            FileHandle.standardError.write(Data("Launch layout failed: \(size), visible=\(visible)\n".utf8)); exit(2)
        }
        print("Launch layout OK: \(Int(size.width))x\(Int(size.height)), pinned=\(desktop.panelPinned)")
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
