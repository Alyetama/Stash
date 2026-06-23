import SwiftUI
import AppKit
import UniformTypeIdentifiers

@main
struct StashApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // The UI lives in a custom status item + floating panel managed by the
        // delegate; this empty Settings scene just satisfies the App protocol.
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let indexer = Indexer()
    private let transforms = TransformSettings()
    private let aiSettings = AISettings()
    private lazy var controller = SearchController(sourcePath: indexer.sourcePath, indexer: indexer, transforms: transforms, ai: aiSettings)
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

        let exportItem = NSMenuItem(title: "Export…", action: #selector(exportData), keyEquivalent: "e")
        exportItem.target = self
        menu.addItem(exportItem)

        if indexer.copyEmAvailable {
            let importItem = NSMenuItem(title: "Import from Copy 'Em", action: #selector(importCopyEm), keyEquivalent: "")
            importItem.target = self
            menu.addItem(importItem)
        }

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Stash", action: #selector(quit), keyEquivalent: "q")
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

    @objc private func exportData() {
        let panel = NSSavePanel()
        panel.title = "Export clipboard history"
        panel.message = "Export your clipboard history to a standalone SQLite database."
        panel.allowedContentTypes = [UTType(filenameExtension: "sqlite") ?? .database]
        panel.canCreateDirectories = true
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyy-MM-dd"
        panel.nameFieldStringValue = "Stash Export \(stamp.string(from: Date())).sqlite"

        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.indexer.export(to: url) { result in
                let alert = NSAlert()
                switch result {
                case .success(let n):
                    alert.messageText = "Exported \(n.formatted()) clips"
                    alert.informativeText = url.path
                case .failure(let error):
                    alert.alertStyle = .warning
                    alert.messageText = "Export failed"
                    alert.informativeText = "\(error)"
                }
                NSApp.activate(ignoringOtherApps: true)
                alert.runModal()
            }
        }
    }

    func showPanel() { panelController.show() }
}
