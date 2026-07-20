import SwiftUI
import AppKit
import ServiceManagement

/// Launch-at-login via the modern Service Management API.
enum LoginItem {
    static var enabled: Bool { SMAppService.mainApp.status == .enabled }
    static func set(_ on: Bool) {
        do { on ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() }
        catch { NSSound.beep() }
    }
}

struct SettingsView: View {
    @ObservedObject var indexer: Indexer
    @ObservedObject var ai: AISettings
    @ObservedObject var theme: ThemeSettings
    @ObservedObject var hotkey: HotKeySettings
    var onExport: () -> Void
    var onImport: () -> Void

    @AppStorage("compactPanel") private var compactPanel = false
    @State private var launchAtLogin = LoginItem.enabled
    @State private var keyInput = ""
    @State private var editingKey = false
    @State private var showKey = false
    @State private var confirmClear = false

    private var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left column.
            Form {
                Section("General") {
                    Picker("Theme", selection: $theme.theme) {
                        ForEach(AppTheme.allCases) { Text($0.label).tag($0) }
                    }
                    Toggle("Launch Stash at login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { LoginItem.set($0) }
                    Toggle("Pause clipboard capture", isOn: $indexer.capturePaused)
                    Toggle("Open under the menu bar (compact)", isOn: $compactPanel)
                    Text(compactPanel
                         ? "The search panel drops down from the menu-bar icon in a smaller layout."
                         : "The search panel opens centered on screen (Spotlight-style).")
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle("Large image previews", isOn: $indexer.largeImages)
                Text("Show copied images as a big preview instead of a small thumbnail.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Keep duplicate clips", isOn: $indexer.keepDuplicates)
                Toggle("Fetch page titles for links", isOn: $indexer.fetchLinkTitles)
                Text(indexer.fetchLinkTitles
                     ? "Copied links are requested to read their title — that sends the URL to the site."
                     : "Off: nothing leaves your Mac. You can still fetch one title by right-clicking a link.")
                    .font(.caption).foregroundStyle(.secondary)
                    Text(indexer.keepDuplicates
                         ? "Every copy is saved as a separate entry."
                         : "Re-copying something already saved moves it to the top instead of duplicating.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Shortcut") {
                    Toggle("Enable global shortcut", isOn: $hotkey.enabled)
                    LabeledContent("Shortcut") {
                        HStack(spacing: 8) {
                            ShortcutField(display: hotkey.display) { code, mods, disp in
                                hotkey.set(keyCode: code, modifiers: mods, display: disp)
                            }
                            .frame(width: 120, height: 22)
                            Button("Reset") { hotkey.reset() }
                        }
                    }
                    .disabled(!hotkey.enabled)
                    Text(hotkey.enabled
                         ? "Click the shortcut, then press a new combo (must include ⌘, ⌃, or ⌥)."
                         : "The shortcut is off — open Stash by clicking the menu-bar icon.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .frame(width: 330)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)

            // Right column.
            Form {
                Section("AI regex (OpenCode)") {
                    if ai.hasKey && !editingKey {
                        HStack {
                            Label("API key set", systemImage: "key.fill").foregroundStyle(.green)
                            Spacer()
                            Button("Change") { keyInput = ""; showKey = false; editingKey = true }
                            Button("Remove", role: .destructive) { ai.setKey("") }
                        }
                    } else {
                        HStack(spacing: 6) {
                            Group {
                                if showKey { TextField("OpenCode API key", text: $keyInput) }
                                else { SecureField("OpenCode API key", text: $keyInput) }
                            }
                            Button { showKey.toggle() } label: { Image(systemName: showKey ? "eye.slash" : "eye") }
                                .buttonStyle(.borderless)
                            Button("Save") { ai.setKey(keyInput); editingKey = false }
                                .disabled(keyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    Picker("Model", selection: $ai.model) {
                        ForEach(AISettings.freeModels) { Text($0.label).tag($0.id) }
                    }
                }

                Section("Data") {
                    LabeledContent("Clips stored", value: indexer.indexedCount.formatted())
                    HStack {
                        Button("Export…", action: onExport)
                        Button("Import from Copy 'Em…", action: onImport)
                        Spacer()
                    }
                    Text("Stored at ~/Library/Application Support/Stash")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("About") {
                    LabeledContent("Version", value: version)
                    Link("Website", destination: URL(string: "https://alyetama.github.io/Stash/")!)
                    Link("Source on GitHub", destination: URL(string: "https://github.com/Alyetama/Stash")!)
                }
            }
            .formStyle(.grouped)
            .frame(width: 330)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)
        }
        .fixedSize()
    }
}

/// Owns the Settings NSWindow (the app is a menu-bar agent, so we manage it manually).
final class SettingsWindowController {
    private var window: NSWindow?
    private let indexer: Indexer
    private let ai: AISettings
    private let theme: ThemeSettings
    private let hotkey: HotKeySettings
    private let onExport: () -> Void
    private let onImport: () -> Void

    init(indexer: Indexer, ai: AISettings, theme: ThemeSettings, hotkey: HotKeySettings,
         onExport: @escaping () -> Void, onImport: @escaping () -> Void) {
        self.indexer = indexer
        self.ai = ai
        self.theme = theme
        self.hotkey = hotkey
        self.onExport = onExport
        self.onImport = onImport
    }

    func show() {
        if window == nil {
            let view = SettingsView(indexer: indexer, ai: ai, theme: theme, hotkey: hotkey, onExport: onExport, onImport: onImport)
            let w = NSWindow(contentViewController: NSHostingController(rootView: view))
            w.title = "Stash Settings"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
