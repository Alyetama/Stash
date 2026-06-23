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
    private let themeSettings = ThemeSettings()
    private lazy var controller = SearchController(sourcePath: indexer.sourcePath, indexer: indexer, transforms: transforms, ai: aiSettings, theme: themeSettings)
    private lazy var panelController = PanelController(controller: controller, indexer: indexer)
    private lazy var settingsWindow = SettingsWindowController(
        indexer: indexer, ai: aiSettings, theme: themeSettings, hotkey: hotkeySettings,
        onExport: { [weak self] in self?.exportData() },
        onImport: { [weak self] in self?.importFromCEP() })
    private let hotkeySettings = HotKeySettings()
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

        panelController.onOpenSettings = { [weak self] in self?.settingsWindow.show() }
        hotkeySettings.onChange = { [weak self] in self?.registerHotKey() }
        registerHotKey()
    }

    private func registerHotKey() {
        HotKeyCenter.shared.setMainHotKey(
            keyCode: hotkeySettings.keyCode,
            modifiers: hotkeySettings.modifiers
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

        let exportItem = NSMenuItem(title: "Export…", action: #selector(exportData), keyEquivalent: "e")
        exportItem.target = self
        menu.addItem(exportItem)

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

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
        case .ready:     return "\(indexer.indexedCount.formatted()) clips · \(indexer.capturePaused ? "paused" : "capturing")"
        case .error:     return "Error — see logs"
        }
    }

    @objc private func openSearch() { panelController.show() }
    @objc private func openSettings() { settingsWindow.show() }
    @objc private func quit() { NSApp.terminate(nil) }

    /// Prompt for a Copy 'Em `.cep` export and import its clips.
    private func importFromCEP() {
        let panel = NSOpenPanel()
        panel.title = "Import a Copy 'Em export"
        panel.message = "Choose a Copy 'Em “.cep” export (or its Copy-em-Paste.storedata)."
        panel.prompt = "Import"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.treatsFilePackagesAsDirectories = false   // a .cep package is one item
        panel.allowsMultipleSelection = false

        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] resp in
            guard resp == .OK, let url = panel.url, let self else { return }
            let store = Self.storedataPath(for: url)

            // Ask how to handle duplicates before importing.
            let ask = NSAlert()
            ask.messageText = "Import duplicate clips?"
            ask.informativeText = "Copy 'Em often stores the same text many times. Keep every copy, or import each unique clip only once?"
            ask.addButton(withTitle: "Remove Duplicates")   // .alertFirstButtonReturn
            ask.addButton(withTitle: "Keep Duplicates")     // .alertSecondButtonReturn
            ask.addButton(withTitle: "Cancel")              // .alertThirdButtonReturn
            NSApp.activate(ignoringOtherApps: true)
            let choice = ask.runModal()
            guard choice != .alertThirdButtonReturn else { return }
            let keepDuplicates = (choice == .alertSecondButtonReturn)

            self.indexer.importFromStore(store, keepDuplicates: keepDuplicates) { result in
                let alert = NSAlert()
                switch result {
                case .success(let r):
                    alert.messageText = r.added == 0 && r.upgraded == 0
                        ? "Nothing new to import"
                        : "Imported \(r.added.formatted()) new \(r.added == 1 ? "clip" : "clips")"
                    if r.upgraded > 0 {
                        alert.informativeText = "Upgraded \(r.upgraded.formatted()) previously-truncated \(r.upgraded == 1 ? "entry" : "entries") to full text."
                    } else if r.added == 0 {
                        alert.informativeText = "Everything in that export was already in Stash."
                    }
                case .failure(let error):
                    alert.alertStyle = .warning
                    alert.messageText = "Import failed"
                    alert.informativeText = error.localizedDescription
                }
                NSApp.activate(ignoringOtherApps: true)
                alert.runModal()
            }
        }
    }

    /// Resolve the Core Data store inside a chosen .cep package (or the file itself).
    private static func storedataPath(for url: URL) -> String {
        let p = url.path
        if p.hasSuffix(".storedata") { return p }
        return p + "/Copy-em-Paste.storedata"
    }

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
