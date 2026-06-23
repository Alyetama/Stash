import SwiftUI
import AppKit

@main
struct CopyEmSearchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // The UI lives in a custom status item + floating panel managed by the
        // delegate; this empty Settings scene just satisfies the App protocol.
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let indexer = Indexer()
    private lazy var controller = SearchController(sourcePath: indexer.sourcePath)
    private lazy var panelController = PanelController(controller: controller, indexer: indexer)
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        indexer.start()

        // Menu-bar status item: left-click opens search, right-click shows the menu.
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = AppIcon.menuBar()
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        HotKeyCenter.shared.register(
            keyCode: HotKeyCenter.defaultKeyCode,
            modifiers: HotKeyCenter.defaultModifiers
        ) { [weak self] in
            self?.panelController.toggle()
        }
    }

    // MARK: status item

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let rightClick = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true
        if rightClick {
            showMenu()
        } else {
            panelController.toggle()
        }
    }

    private func showMenu() {
        let menu = NSMenu()

        let search = NSMenuItem(title: "Search…", action: #selector(openSearch), keyEquivalent: "")
        search.target = self
        menu.addItem(search)

        menu.addItem(.separator())

        let status = NSMenuItem(title: statusText(), action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        let sync = NSMenuItem(title: lastSyncText(), action: nil, keyEquivalent: "")
        sync.isEnabled = false
        menu.addItem(sync)

        if indexer.copyEmAvailable {
            let importItem = NSMenuItem(title: "Import from Copy 'Em", action: #selector(importCopyEm), keyEquivalent: "")
            importItem.target = self
            menu.addItem(importItem)
        }

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit CopyEm Search", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        // Attach transiently so left-click keeps its custom behavior.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func statusText() -> String {
        switch indexer.phase {
        case .starting:  return "Starting…"
        case .importing: return "Importing \(indexer.buildDone.formatted())/\(indexer.buildTotal.formatted())…"
        case .ready:     return "\(indexer.indexedCount.formatted()) clips · capturing live"
        case .error:     return "Error — see logs"
        }
    }

    private func lastSyncText() -> String {
        guard let d = indexer.lastSync else { return "Live sync: waiting…" }
        return "Last synced \(d.formatted(date: .omitted, time: .standard))"
    }

    @objc private func openSearch() { panelController.show() }
    @objc private func importCopyEm() { indexer.importFromCopyEm() }
    @objc private func quit() { NSApp.terminate(nil) }

    func showPanel() { panelController.show() }
}
