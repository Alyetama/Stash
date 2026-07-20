import Foundation

/// Fetches the <title> of a web page for clips that are a bare URL.
///
/// This is the only part of Stash besides the AI regex helper that touches the
/// network: fetching a title sends the copied URL to that site. It is therefore
/// off by default and only runs when the user opts in (or asks for one clip
/// explicitly from the context menu).
enum LinkTitle {

    /// Returns the URL when `text` is a single bare http(s) link, otherwise nil.
    static func url(in text: String) -> URL? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t.utf8.count < 2048,
              !t.contains(where: { $0.isWhitespace || $0.isNewline }),
              let u = URL(string: t),
              let scheme = u.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = u.host, !host.isEmpty
        else { return nil }
        return u
    }

    /// GET the page and pull its title. Never sends cookies; capped and time-boxed.
    static func fetch(_ url: URL, completion: @escaping (String?) -> Void) {
        var req = URLRequest(url: url, timeoutInterval: 8)
        req.httpMethod = "GET"
        req.httpShouldHandleCookies = false
        req.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        req.setValue("Stash (macOS clipboard manager)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: req) { data, resp, _ in
            guard let data,
                  let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  (http.mimeType ?? "").localizedCaseInsensitiveContains("html")
            else { return completion(nil) }
            completion(parseTitle(data))
        }.resume()
    }

    /// Extract and tidy the <title> from an HTML document.
    ///
    /// The tag is located in the raw bytes rather than by decoding a fixed head:
    /// some pages (YouTube) emit hundreds of KB of inline script before <title>.
    static func parseTitle(_ data: Data) -> String? {
        let scan = data.prefix(4_000_000)
        guard let offset = byteOffset(of: Array("<title".utf8), in: scan) else { return nil }
        let start = scan.index(scan.startIndex, offsetBy: offset)
        let end = scan.index(start, offsetBy: 16_384, limitedBy: scan.endIndex) ?? scan.endIndex
        let window = scan[start..<end]

        guard let html = String(data: window, encoding: .utf8)
                ?? String(data: window, encoding: .isoLatin1) else { return nil }
        guard let r = html.range(of: "(?s)<title[^>]*>(.*?)</title>",
                                 options: [.regularExpression, .caseInsensitive]) else { return nil }

        var t = String(html[r])
        t = t.replacingOccurrences(of: "(?s)^<title[^>]*>", with: "",
                                   options: [.regularExpression, .caseInsensitive])
        t = t.replacingOccurrences(of: "(?i)</title>$", with: "", options: .regularExpression)
        t = decodeEntities(t)
        t = t.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : String(t.prefix(200))
    }

    /// Case-insensitive ASCII byte search; returns the offset from the slice start.
    private static func byteOffset(of needle: [UInt8], in data: Data) -> Int? {
        guard !needle.isEmpty, data.count >= needle.count else { return nil }
        let lower = needle.map { $0 | 0x20 }
        return data.withUnsafeBytes { raw -> Int? in
            let buf = raw.bindMemory(to: UInt8.self)
            let n = lower.count
            guard buf.count >= n else { return nil }
            outer: for i in 0...(buf.count - n) {
                for k in 0..<n where (buf[i + k] | 0x20) != lower[k] { continue outer }
                return i
            }
            return nil
        }
    }

    private static let named: [String: String] = [
        "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&apos;": "'",
        "&nbsp;": " ", "&mdash;": "—", "&ndash;": "–", "&hellip;": "…",
        "&rsquo;": "’", "&lsquo;": "‘", "&ldquo;": "“", "&rdquo;": "”",
    ]

    private static func decodeEntities(_ s: String) -> String {
        var out = s
        for (k, v) in named { out = out.replacingOccurrences(of: k, with: v, options: .caseInsensitive) }
        // Numeric entities: &#123; and &#x1F600;
        guard out.contains("&#"),
              let re = try? NSRegularExpression(pattern: "&#(x?)([0-9A-Fa-f]+);") else { return out }
        let ns = out as NSString
        var result = ""
        var last = 0
        for m in re.matches(in: out, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let isHex = ns.substring(with: m.range(at: 1)).lowercased() == "x"
            let digits = ns.substring(with: m.range(at: 2))
            if let code = UInt32(digits, radix: isHex ? 16 : 10), let scalar = Unicode.Scalar(code) {
                result.append(Character(scalar))
            }
            last = m.range.location + m.range.length
        }
        result += ns.substring(from: last)
        return result
    }
}
