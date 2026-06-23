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
        // Transparent so the SwiftUI frosted material shows through; dark, sleek look.
        isOpaque = false
        backgroundColor = .clear
        appearance = NSAppearance(named: .darkAqua)
        hasShadow = true
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// A frosted translucent backdrop (used behind the search UI).
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blending: NSVisualEffectView.BlendingMode = .behindWindow
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blending
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material; v.blendingMode = blending
    }
}

/// Shows/hides the search panel and wires up dismiss-on-blur.
final class PanelController: NSObject, NSWindowDelegate {
    private var panel: FloatingPanel?
    private let controller: SearchController
    private let indexer: Indexer
    var onOpenSettings: (() -> Void)?
    var onDeleteGroup: ((String) -> Void)?
    /// Returns the menu-bar status item's frame in screen coordinates, used to
    /// anchor the compact panel under the icon.
    var statusButtonRect: (() -> NSRect?)?
    private var builtCompact: Bool?

    init(controller: SearchController, indexer: Indexer) {
        self.controller = controller
        self.indexer = indexer
    }

    /// Ignore spurious resign-key events for a moment after showing (the menu-bar
    /// dropdown closing transiently steals key focus).
    private var suppressResignUntil = Date.distantPast

    /// While true, don't dismiss on focus loss — set when a modal sub-flow (e.g.
    /// the AI popover, whose Keychain prompt steals focus) is active.
    var holdOpen = false

    func toggle() {
        if let panel, panel.isVisible { hide() } else { show() }
    }

    func show() {
        // Defer slightly so the menu-bar dropdown has finished closing before we
        // take focus — otherwise the panel can be dismissed the instant it appears.
        DispatchQueue.main.async { [weak self] in self?.present() }
    }

    private func present() {
        let compact = UserDefaults.standard.bool(forKey: "compactPanel")
        // Rebuild the panel if the layout mode changed since it was created.
        if let built = builtCompact, built != compact { panel?.orderOut(nil); panel = nil }
        let panel = self.panel ?? makePanel(compact: compact)
        self.panel = panel
        builtCompact = compact

        if compact, let anchor = statusButtonRect?() {
            let size = NSSize(width: 380, height: 520)
            panel.setContentSize(size)
            let vis = (NSScreen.screens.first { $0.frame.contains(anchor.origin) } ?? NSScreen.main)?.visibleFrame ?? .zero
            var x = anchor.midX - size.width / 2
            x = min(max(x, vis.minX + 8), vis.maxX - size.width - 8)
            let y = anchor.minY - size.height - 6   // just below the status item
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            panel.setContentSize(NSSize(width: 720, height: 460))
            if let screen = NSScreen.main ?? NSScreen.screens.first {
                let f = screen.visibleFrame
                let size = panel.frame.size
                let origin = NSPoint(x: f.midX - size.width / 2,
                                     y: f.midY - size.height / 2 + f.height * 0.08)
                panel.setFrameOrigin(origin)
            }
        }
        suppressResignUntil = Date().addingTimeInterval(0.6)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        // Load the latest items (query is blank on open) and focus the field.
        controller.refreshGroups()
        controller.runSearch()
        NotificationCenter.default.post(name: .focusSearchField, object: nil)
    }

    func hide() {
        panel?.orderOut(nil)
        controller.reset()   // start blank next time
    }

    private func makePanel(compact: Bool = false) -> FloatingPanel {
        let panel = FloatingPanel()
        panel.delegate = self
        let root = SearchView(controller: controller, indexer: indexer,
                              transforms: controller.transforms,
                              ai: controller.ai,
                              theme: controller.theme,
                              groups: controller.groups,
                              onOpenSettings: { [weak self] in self?.onOpenSettings?() },
                              onDeleteGroup: { [weak self] name in self?.onDeleteGroup?(name) },
                              onHoldChange: { [weak self] hold in
                                  guard let self else { return }
                                  if hold {
                                      self.holdOpen = true
                                  } else {
                                      // Brief grace for the dismissal transition, then release the
                                      // hold. If focus has moved off the panel (the popover was
                                      // dismissed by clicking elsewhere), close the panel now.
                                      DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                          self.holdOpen = false
                                          if let p = self.panel, p.isVisible, !p.isKeyWindow { self.hide() }
                                      }
                                  }
                              },
                              onClose: { [weak self] in self?.hide() },
                              compact: compact)
        // Let the content fill into the (hidden) title-bar region so there's no
        // empty band above the search bar inside the window.
        panel.contentView = NSHostingView(rootView: root.ignoresSafeArea(.container, edges: .top))
        return panel
    }

    func windowDidResignKey(_ notification: Notification) {
        // Clicking elsewhere dismisses the overlay — but ignore the transient
        // resign during menu-close, and keep open while a modal sub-flow is active.
        if holdOpen || Date() < suppressResignUntil { return }
        hide()
    }
}

extension Notification.Name {
    static let focusSearchField = Notification.Name("Stash.focusSearchField")
}

/// An NSTextField bridged into SwiftUI that reports arrow/return/escape so the
/// results list can be driven entirely from the keyboard while typing.
struct SearchField: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat = 22
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
        field.font = .systemFont(ofSize: fontSize, weight: .regular)
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
