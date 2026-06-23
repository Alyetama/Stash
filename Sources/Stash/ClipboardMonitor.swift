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
        // GIF before TIFF: a copied GIF often carries a TIFF rep too; keep the real
        // GIF bytes (we still preview it as a static first-frame thumbnail).
        if let d = pb.data(forType: NSPasteboard.PasteboardType("com.compuserve.gif")) { return (d, "gif") }
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

/// Extracts the largest embedded image from a Copy 'Em pasteboard-data blob.
/// The blob is an NSKeyedArchiver plist that may contain nested bplist archives;
/// we recurse looking for raw image bytes (PNG/JPEG/GIF/TIFF).
enum CopyEmImage {
    static func extractLargest(from blob: Data) -> (data: Data, ext: String)? {
        var best: (Data, String)?
        scan(blob, depth: 0) { d, ext in
            if best == nil || d.count > best!.0.count { best = (d, ext) }
        }
        guard let b = best, b.0.count > 256 else { return nil }
        return (b.0, b.1)
    }

    private static func magic(_ d: Data) -> String? {
        guard d.count >= 4 else { return nil }
        let b = [UInt8](d.prefix(4))
        if b == [0x89, 0x50, 0x4E, 0x47] { return "png" }
        if b[0] == 0xFF, b[1] == 0xD8, b[2] == 0xFF { return "jpg" }
        if b == [0x47, 0x49, 0x46, 0x38] { return "gif" }
        if b == [0x49, 0x49, 0x2A, 0x00] || b == [0x4D, 0x4D, 0x00, 0x2A] { return "tiff" }
        return nil
    }

    private static let bplistMagic: [UInt8] = Array("bplist00".utf8)

    private static func scan(_ data: Data, depth: Int, _ found: (Data, String) -> Void) {
        if depth > 5 { return }
        if let ext = magic(data) { found(data, ext); return }
        guard data.count >= 8, [UInt8](data.prefix(8)) == bplistMagic,
              let obj = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        else { return }
        walk(obj, depth: depth + 1, found)
    }

    private static func walk(_ obj: Any, depth: Int, _ found: (Data, String) -> Void) {
        if let d = obj as? Data {
            scan(d, depth: depth, found)
        } else if let arr = obj as? [Any] {
            for v in arr { walk(v, depth: depth, found) }
        } else if let dict = obj as? [AnyHashable: Any] {
            for v in dict.values { walk(v, depth: depth, found) }
        }
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
