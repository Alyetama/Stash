import SwiftUI
import AppKit

/// Persisted global summon shortcut. `onChange` is called when it's reassigned
/// so the app can re-register the hot key.
final class HotKeySettings: ObservableObject {
    @Published private(set) var keyCode: UInt32
    @Published private(set) var modifiers: UInt32   // Carbon mask
    @Published private(set) var display: String
    /// When off, no global shortcut is registered (open via the menu-bar icon).
    @Published var enabled: Bool { didSet { d.set(enabled, forKey: "hk.enabled"); onChange?() } }
    var onChange: (() -> Void)?

    private let d = UserDefaults.standard
    init() {
        keyCode = UInt32(d.object(forKey: "hk.keyCode") as? Int ?? Int(HotKeyCenter.defaultKeyCode))
        modifiers = UInt32(d.object(forKey: "hk.modifiers") as? Int ?? Int(HotKeyCenter.defaultModifiers))
        display = d.string(forKey: "hk.display") ?? HotKeyCenter.defaultDisplay
        enabled = d.object(forKey: "hk.enabled") as? Bool ?? true
    }

    func set(keyCode: UInt32, modifiers: UInt32, display: String) {
        self.keyCode = keyCode; self.modifiers = modifiers; self.display = display
        d.set(Int(keyCode), forKey: "hk.keyCode")
        d.set(Int(modifiers), forKey: "hk.modifiers")
        d.set(display, forKey: "hk.display")
        onChange?()
    }

    func reset() {
        set(keyCode: HotKeyCenter.defaultKeyCode, modifiers: HotKeyCenter.defaultModifiers,
            display: HotKeyCenter.defaultDisplay)
    }
}

/// A click-to-record shortcut field (captures the next key combo with modifiers).
struct ShortcutField: NSViewRepresentable {
    var display: String
    var onCapture: (UInt32, UInt32, String) -> Void

    func makeNSView(context: Context) -> RecorderButton {
        let b = RecorderButton()
        b.bezelStyle = .rounded
        b.setButtonType(.momentaryPushIn)
        b.onCapture = onCapture
        b.shortcutTitle = display
        return b
    }
    func updateNSView(_ b: RecorderButton, context: Context) {
        b.onCapture = onCapture
        if !b.isRecording { b.shortcutTitle = display }
    }
}

final class RecorderButton: NSButton {
    var onCapture: ((UInt32, UInt32, String) -> Void)?
    var shortcutTitle: String = "" { didSet { if !isRecording { title = shortcutTitle } } }
    private(set) var isRecording = false {
        didSet { title = isRecording ? "Type shortcut…" : shortcutTitle }
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        isRecording.toggle()
        if isRecording { window?.makeFirstResponder(self) }
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { super.keyDown(with: event); return }
        if event.keyCode == 53 { isRecording = false; return }   // Esc cancels
        let carbon = HotKeyCenter.carbonModifiers(event.modifierFlags)
        let chars = (event.charactersIgnoringModifiers ?? "").uppercased()
        guard carbon != 0, !chars.isEmpty else { NSSound.beep(); return }   // require a modifier
        let disp = HotKeyCenter.modifierSymbols(event.modifierFlags) + chars
        onCapture?(UInt32(event.keyCode), carbon, disp)
        shortcutTitle = disp
        isRecording = false
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return super.resignFirstResponder()
    }
}
