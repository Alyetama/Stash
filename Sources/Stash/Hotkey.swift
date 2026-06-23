import AppKit
import Carbon.HIToolbox

/// Registers system-wide hot keys via Carbon (works without Accessibility or any
/// entitlement). The C event callback can't capture state, so registrations are
/// kept in a shared table keyed by hot-key id.
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var nextID: UInt32 = 1
    private var installed = false
    private var mainID: UInt32?

    /// Default summon shortcut: ⌃⌥C.
    static let defaultKeyCode = UInt32(kVK_ANSI_C)
    static let defaultModifiers = UInt32(optionKey | controlKey)
    static let defaultDisplay = "⌃⌥C"

    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) -> Bool {
        installHandlerIfNeeded()
        let id = nextID; nextID += 1
        let hotKeyID = EventHotKeyID(signature: OSType(0x43455343 /* 'CESC' */), id: id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        refs[id] = ref
        handlers[id] = action
        return true
    }

    /// (Re)register THE main summon hot key, replacing any previous one.
    func setMainHotKey(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        installHandlerIfNeeded()
        if let id = mainID, let ref = refs[id] {
            UnregisterEventHotKey(ref); refs[id] = nil; handlers[id] = nil
        }
        let id = nextID; nextID += 1
        let hotKeyID = EventHotKeyID(signature: OSType(0x43455343), id: id)
        var ref: EventHotKeyRef?
        if RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref) == noErr,
           let ref {
            refs[id] = ref; handlers[id] = action; mainID = id
        }
    }

    /// Remove the main summon hot key (used when the shortcut is disabled).
    func clearMainHotKey() {
        guard let id = mainID, let ref = refs[id] else { return }
        UnregisterEventHotKey(ref)
        refs[id] = nil; handlers[id] = nil; mainID = nil
    }

    /// Convert NSEvent modifier flags to Carbon masks for RegisterEventHotKey.
    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        return m
    }

    /// Human-readable modifier symbols (⌃⌥⇧⌘) for a flag set.
    static func modifierSymbols(_ flags: NSEvent.ModifierFlags) -> String {
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option) { s += "⌥" }
        if flags.contains(.shift) { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        return s
    }

    private func installHandlerIfNeeded() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            guard let event else { return OSStatus(eventNotHandledErr) }
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            HotKeyCenter.shared.handlers[hkID.id]?()
            return noErr
        }, 1, &spec, nil, nil)
    }
}
