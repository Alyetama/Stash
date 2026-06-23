import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Watches the system clipboard and reports newly-copied text or images. macOS has
/// no change notification for the pasteboard, so we poll its changeCount (cheap).
final class ClipboardMonitor {
    private var timer: Timer?
    private var lastChangeCount: Int
    private let interval: TimeInterval
    private let onText: (String, String?) -> Void
    private let onImage: (Data, String, String?) -> Void

    /// - onText: (text, frontmost app). onImage: (image data, file extension, app).
    init(interval: TimeInterval = 0.4,
         onText: @escaping (String, String?) -> Void,
         onImage: @escaping (Data, String, String?) -> Void) {
        self.interval = interval
        self.onText = onText
        self.onImage = onImage
        self.lastChangeCount = NSPasteboard.general.changeCount
    }

    func start() {
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() { timer?.invalidate(); timer = nil }

    /// Tell the monitor the current pasteboard state was produced by us (e.g. we
    /// just copied a result out) so it isn't recorded again as a new clip.
    func markCurrentAsSeen() { lastChangeCount = NSPasteboard.general.changeCount }

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount
        let app = NSWorkspace.shared.frontmostApplication?.localizedName

        // Prefer text (more searchable); fall back to image data.
        if let text = pb.string(forType: .string), !text.isEmpty {
            onText(text, app)
        } else if let (data, ext) = Self.imageData(from: pb) {
            onImage(data, ext, app)
        }
    }

    /// Pull image bytes off the pasteboard, normalising TIFF to PNG.
    private static func imageData(from pb: NSPasteboard) -> (Data, String)? {
        if let d = pb.data(forType: .png) { return (d, "png") }
        if let d = pb.data(forType: NSPasteboard.PasteboardType("public.heic")) { return (d, "heic") }
        if let d = pb.data(forType: .tiff) {
            if let rep = NSBitmapImageRep(data: d),
               let png = rep.representation(using: .png, properties: [:]) {
                return (png, "png")
            }
            return (d, "tiff")
        }
        return nil
    }
}

/// Thread-safe thumbnailing + dimension reading via ImageIO (no AppKit drawing).
enum ImageThumb {
    /// Returns (thumbnail PNG, fullWidth, fullHeight).
    static func make(from data: Data, maxPixel: Int) -> (png: Data, w: Int, h: Int)? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        let w = (props?[kCGImagePropertyPixelWidth] as? Int) ?? 0
        let h = (props?[kCGImagePropertyPixelHeight] as? Int) ?? 0

        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }

        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(dest, thumb, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return (out as Data, w, h)
    }
}
