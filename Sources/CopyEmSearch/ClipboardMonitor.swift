import AppKit

/// Watches the system clipboard and reports newly-copied text. macOS has no
/// change notification for the pasteboard, so we poll its changeCount (cheap).
final class ClipboardMonitor {
    private var timer: Timer?
    private var lastChangeCount: Int
    private let interval: TimeInterval
    private let onCopy: (String, String?) -> Void

    /// - onCopy: called on the main thread with (text, frontmost app name).
    init(interval: TimeInterval = 0.4, onCopy: @escaping (String, String?) -> Void) {
        self.interval = interval
        self.onCopy = onCopy
        self.lastChangeCount = NSPasteboard.general.changeCount
    }

    func start() {
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() { timer?.invalidate(); timer = nil }

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        // Only record plain-text clips (images/files have no searchable text).
        guard let text = pb.string(forType: .string), !text.isEmpty else { return }
        let app = NSWorkspace.shared.frontmostApplication?.localizedName
        onCopy(text, app)
    }
}
