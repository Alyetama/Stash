import SwiftUI

/// Persisted settings for the optional AI-assisted regex feature.
/// The key is the user's own OpenCode API key, stored locally in UserDefaults.
final class AISettings: ObservableObject {
    /// Whether a key is saved — determined by a prompt-free existence check, NOT
    /// by reading the secret, so the app never shows a Keychain prompt at launch.
    @Published private(set) var hasKey: Bool
    @Published var model: String { didSet { d.set(model, forKey: "ai.model") } }

    /// OpenCode Zen — OpenAI-compatible chat-completions endpoint.
    let endpoint = "https://opencode.ai/zen/v1/chat/completions"

    /// Free models OpenCode Zen offers (id used by the API, plus a friendly label).
    struct Model: Identifiable, Hashable { let id: String; let label: String }
    static let freeModels: [Model] = [
        .init(id: "deepseek-v4-flash-free", label: "DeepSeek V4 Flash"),
        .init(id: "big-pickle", label: "Big Pickle"),
        .init(id: "mimo-v2.5-free", label: "MiMo V2.5"),
        .init(id: "north-mini-code-free", label: "North Mini Code"),
        .init(id: "nemotron-3-ultra-free", label: "Nemotron 3 Ultra"),
    ]

    private static let keyAccount = "opencode.apiKey"
    private let d = UserDefaults.standard
    private var cachedKey: String?   // populated lazily on first real use

    init() {
        // One-time migration: move any key from the old plaintext plist into the
        // Keychain (writes don't prompt; we never read the secret here).
        if let legacy = d.string(forKey: "ai.apiKey"), !legacy.isEmpty {
            Keychain.set(legacy, account: Self.keyAccount)
            d.removeObject(forKey: "ai.apiKey")
        }
        hasKey = Keychain.exists(account: Self.keyAccount)   // no prompt
        let stored = d.string(forKey: "ai.model") ?? "deepseek-v4-flash-free"
        model = Self.freeModels.contains(where: { $0.id == stored }) ? stored : "deepseek-v4-flash-free"
    }

    var enabled: Bool { hasKey }

    /// Read the secret (may prompt the first time) — only call when the user is
    /// actively using the AI feature.
    func currentKey() -> String {
        if cachedKey == nil { cachedKey = Keychain.get(account: Self.keyAccount) ?? "" }
        return cachedKey ?? ""
    }

    func setKey(_ value: String) {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        Keychain.set(v, account: Self.keyAccount)
        cachedKey = v
        hasKey = !v.isEmpty
    }
}

enum AIError: Error {
    case noKey, badURL, empty, parse, api(String)
    var message: String {
        switch self {
        case .noKey:        return "Add your OpenCode API key first."
        case .badURL:       return "Invalid endpoint."
        case .empty:        return "No response from the server."
        case .parse:        return "Couldn't read the response."
        case .api(let m):   return m
        }
    }
}

/// Turns a natural-language description into a regular expression via OpenCode.
struct AIService {
    let settings: AISettings

    private static let system = """
    You convert a natural-language description into ONE regular expression compatible \
    with ICU / NSRegularExpression (the engine used by Swift). Output ONLY the regex \
    pattern itself — no delimiters, no surrounding quotes, no code fences, no flags, \
    and no explanation.
    """

    func generateRegex(from prompt: String, completion: @escaping (Result<String, Error>) -> Void) {
        let key = settings.currentKey().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return completion(.failure(AIError.noKey)) }
        guard let url = URL(string: settings.endpoint) else { return completion(.failure(AIError.badURL)) }

        var req = URLRequest(url: url, timeoutInterval: 30)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "model": settings.model,
            "temperature": 0,
            // Generous budget: several of OpenCode's free models are reasoning
            // models that spend tokens "thinking" before emitting the answer.
            "max_tokens": 2000,
            "messages": [
                ["role": "system", "content": Self.system],
                ["role": "user", "content": prompt],
            ],
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: req) { data, resp, err in
            if let err { return completion(.failure(err)) }
            guard let data else { return completion(.failure(AIError.empty)) }
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let raw = String(data: data, encoding: .utf8) ?? ""

            guard let json = try? JSONSerialization.jsonObject(with: data) else {
                return completion(.failure(AIError.api("HTTP \(status): \(raw.prefix(180))")))
            }
            guard let obj = json as? [String: Any] else {
                return completion(.failure(AIError.api("HTTP \(status): \(raw.prefix(180))")))
            }

            // Error shapes: {"error":{"message":...}} or {"error":"..."}.
            if let e = obj["error"] {
                let m = (e as? [String: Any])?["message"] as? String ?? (e as? String) ?? "\(e)"
                return completion(.failure(AIError.api(m)))
            }

            // Pull content from chat (message.content string OR array of parts) or text.
            if let choices = obj["choices"] as? [[String: Any]], let first = choices.first {
                var content = (first["message"] as? [String: Any])?["content"] as? String
                if content == nil, let parts = (first["message"] as? [String: Any])?["content"] as? [[String: Any]] {
                    content = parts.compactMap { $0["text"] as? String }.joined()
                }
                if content == nil { content = first["text"] as? String }
                if let c = content {
                    let cleaned = Self.clean(c)
                    if !cleaned.isEmpty { return completion(.success(cleaned)) }
                    let reason = first["finish_reason"] as? String
                    let msg = reason == "length"
                        ? "The model ran out of room while reasoning. Try again, or pick a different model."
                        : "The model returned an empty result. Try again or pick a different model."
                    return completion(.failure(AIError.api(msg)))
                }
            }
            completion(.failure(AIError.api("Unexpected response (HTTP \(status)): \(raw.prefix(180))")))
        }.resume()
    }

    /// Strip code fences / quotes / extra prose the model might add.
    static func clean(_ raw: String) -> String {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("```") {
            t = t.replacingOccurrences(of: "```[a-zA-Z]*\\n?", with: "", options: .regularExpression)
            t = t.replacingOccurrences(of: "```", with: "")
        }
        // Use the first non-empty line, stripped of wrapping quotes/backticks.
        let line = t.split(whereSeparator: \.isNewline).first.map(String.init) ?? t
        return line.trimmingCharacters(in: CharacterSet(charactersIn: "`\"' \t"))
    }
}

/// Popover shown from the regex tab: paste a key, describe a pattern, generate.
struct AIRegexView: View {
    @ObservedObject var ai: AISettings
    @ObservedObject var controller: SearchController
    var onClose: () -> Void

    @State private var prompt = ""
    @State private var generating = false
    @State private var error = ""
    @State private var showKey = false
    @State private var editingKey = false
    @State private var keyInput = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Generate regex with AI").font(.headline)

            if ai.hasKey && !editingKey {
                // Key already saved — show a compact status with Edit / Remove.
                HStack(spacing: 8) {
                    Image(systemName: "key.fill").foregroundStyle(.green)
                    Text("API key set").font(.callout)
                    Spacer()
                    Button("Edit") { keyInput = ai.currentKey(); showKey = false; editingKey = true }.buttonStyle(.link)
                    Button("Remove", role: .destructive) { ai.setKey(""); keyInput = ""; editingKey = false }.buttonStyle(.link)
                }
            } else {
                HStack(spacing: 6) {
                    Group {
                        if showKey { TextField("OpenCode API key", text: $keyInput) }
                        else { SecureField("OpenCode API key", text: $keyInput) }
                    }
                    .textFieldStyle(.roundedBorder)
                    Button { showKey.toggle() } label: { Image(systemName: showKey ? "eye.slash" : "eye") }
                        .buttonStyle(.borderless)
                    Button("Save") { ai.setKey(keyInput); editingKey = false }
                        .buttonStyle(.link)
                        .disabled(keyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            Picker("Model", selection: $ai.model) {
                ForEach(AISettings.freeModels) { Text($0.label).tag($0.id) }
            }
            .pickerStyle(.menu)

            Divider().padding(.vertical, 1)

            Text("Describe what to match").font(.caption).foregroundStyle(.secondary)
            TextField("e.g. email addresses, or dates like 2026-01-31", text: $prompt)
                .textFieldStyle(.roundedBorder)
                .onSubmit(generate)

            HStack(spacing: 8) {
                Button(action: generate) {
                    Label("Generate & search", systemImage: "sparkles")
                }
                .disabled(generating || !ai.enabled || prompt.trimmingCharacters(in: .whitespaces).isEmpty)
                if generating { ProgressView().controlSize(.small) }
            }

            if !error.isEmpty {
                Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            Text("Calls OpenCode (\(ai.model)). Your key is stored in your macOS Keychain.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(width: 360)
        .padding(16)
    }

    private func generate() {
        let p = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty, ai.enabled else { return }
        generating = true; error = ""
        AIService(settings: ai).generateRegex(from: p) { result in
            DispatchQueue.main.async {
                generating = false
                switch result {
                case .success(let rx):
                    controller.mode = .regex
                    controller.query = rx       // triggers a regex search
                    onClose()
                case .failure(let e):
                    error = (e as? AIError)?.message ?? e.localizedDescription
                }
            }
        }
    }
}
