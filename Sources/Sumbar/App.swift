import AppKit
import SwiftUI

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = MarketStore()
    var statusItem: NSStatusItem!
    let popover = NSPopover()
    var wakeObserver: NSObjectProtocol?
    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "chart.xyaxis.line", accessibilityDescription: "Sumbar — финансы Узбекистана")
            button.target = self; button.action = #selector(togglePanel)
        }
        let height = min(CGFloat(760), (NSScreen.main?.visibleFrame.height ?? 820) - 40)
        popover.contentSize = NSSize(width: 520, height: height)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: PanelView(store: store, panelHeight: height))
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.store.refresh() }
        }
        store.start()
        if CommandLine.arguments.contains("--preview") { togglePanel() }
    }
    @objc func togglePanel() {
        guard let button = statusItem.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            NSApp.activate(ignoringOtherApps: true)
            Task { await store.refresh() }
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
