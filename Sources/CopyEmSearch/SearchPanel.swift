import AppKit
import SwiftUI

/// A borderless floating panel that can take keyboard focus (Spotlight-style).
final class FloatingPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 460),
            styleMask: [.titled, .fullSizeContentView, .resizable],
            backing: .buffered, defer: false)
        becomesKeyOnlyIfNeeded = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        isMovableByWindowBackground = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
        backgroundColor = .windowBackgroundColor
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Shows/hides the search panel and wires up dismiss-on-blur.
final class PanelController: NSObject, NSWindowDelegate {
    private var panel: FloatingPanel?
    private let controller: SearchController
    private let indexer: Indexer

    init(controller: SearchController, indexer: Indexer) {
        self.controller = controller
        self.indexer = indexer
    }

    /// Ignore spurious resign-key events for a moment after showing (the menu-bar
    /// dropdown closing transiently steals key focus).
    private var suppressResignUntil = Date.distantPast

    func toggle() {
        if let panel, panel.isVisible { hide() } else { show() }
    }

    func show() {
        // Defer slightly so the menu-bar dropdown has finished closing before we
        // take focus — otherwise the panel can be dismissed the instant it appears.
        DispatchQueue.main.async { [weak self] in self?.present() }
    }

    private func present() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let f = screen.visibleFrame
            let size = panel.frame.size
            let origin = NSPoint(x: f.midX - size.width / 2,
                                 y: f.midY - size.height / 2 + f.height * 0.08)
            panel.setFrameOrigin(origin)
        }
        suppressResignUntil = Date().addingTimeInterval(0.6)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        // Load the latest items (query is blank on open) and focus the field.
        controller.runSearch()
        NotificationCenter.default.post(name: .focusSearchField, object: nil)
    }

    func hide() {
        panel?.orderOut(nil)
        controller.reset()   // start blank next time
    }

    private func makePanel() -> FloatingPanel {
        let panel = FloatingPanel()
        panel.delegate = self
        let root = SearchView(controller: controller, indexer: indexer,
                              onClose: { [weak self] in self?.hide() })
        panel.contentView = NSHostingView(rootView: root)
        return panel
    }

    func windowDidResignKey(_ notification: Notification) {
        // Clicking elsewhere dismisses the overlay — but ignore the transient
        // resign that happens while the menu-bar dropdown is closing.
        if Date() < suppressResignUntil { return }
        hide()
    }
}

extension Notification.Name {
    static let focusSearchField = Notification.Name("CopyEmSearch.focusSearchField")
}

/// An NSTextField bridged into SwiftUI that reports arrow/return/escape so the
/// results list can be driven entirely from the keyboard while typing.
struct SearchField: NSViewRepresentable {
    @Binding var text: String
    var onMoveUp: () -> Void
    var onMoveDown: () -> Void
    var onSubmit: () -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = "Search your clipboard history…"
        field.delegate = context.coordinator
        field.focusRingType = .none
        field.isBezeled = false
        field.drawsBackground = false
        field.font = .systemFont(ofSize: 22, weight: .regular)
        field.lineBreakMode = .byTruncatingTail
        field.cell?.usesSingleLineMode = true
        context.coordinator.field = field

        NotificationCenter.default.addObserver(
            forName: .focusSearchField, object: nil, queue: .main) { _ in
            DispatchQueue.main.async {
                field.window?.makeFirstResponder(field)
                field.currentEditor()?.selectAll(nil)
            }
        }
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text { nsView.stringValue = text }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        let parent: SearchField
        weak var field: NSTextField?
        init(_ parent: SearchField) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            if let f = obj.object as? NSTextField { parent.text = f.stringValue }
        }

        func control(_ control: NSControl, textView: NSTextView,
                     doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveDown(_:)):
                parent.onMoveDown(); return true
            case #selector(NSResponder.moveUp(_:)):
                parent.onMoveUp(); return true
            case #selector(NSResponder.insertNewline(_:)):
                parent.onSubmit(); return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel(); return true
            default:
                return false
            }
        }
    }
}
