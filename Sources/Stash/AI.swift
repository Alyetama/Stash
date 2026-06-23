import SwiftUI

/// Persisted settings for the optional AI-assisted regex feature.
/// The key is the user's own OpenCode API key, stored locally in UserDefaults.
final class AISettings: ObservableObject {
    @Published var apiKey: String { didSet { d.set(apiKey, forKey: "ai.apiKey") } }
    @Published var model: String  { didSet { d.set(model, forKey: "ai.model") } }

    /// OpenCode Zen — OpenAI-compatible chat-completions endpoint.
    let endpoint = "https://opencode.ai/zen/v1/chat/completions"

    private let d = UserDefaults.standard
    init() {
        apiKey = d.string(forKey: "ai.apiKey") ?? ""
        model = d.string(forKey: "ai.model") ?? "deepseek-v4-flash-free"
    }

    var enabled: Bool { !apiKey.trimmingCharacters(in: .whitespaces).isEmpty }
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
        let key = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return completion(.failure(AIError.noKey)) }
        guard let url = URL(string: settings.endpoint) else { return completion(.failure(AIError.badURL)) }

        var req = URLRequest(url: url, timeoutInterval: 30)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "model": settings.model,
            "temperature": 0,
            "max_tokens": 200,
            "messages": [
                ["role": "system", "content": Self.system],
                ["role": "user", "content": prompt],
            ],
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: req) { data, _, err in
            if let err { return completion(.failure(err)) }
            guard let data else { return completion(.failure(AIError.empty)) }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return completion(.failure(AIError.parse))
            }
            if let choices = json["choices"] as? [[String: Any]],
               let msg = choices.first?["message"] as? [String: Any],
               let content = msg["content"] as? String {
                let cleaned = Self.clean(content)
                cleaned.isEmpty ? completion(.failure(AIError.parse)) : completion(.success(cleaned))
            } else if let e = json["error"] as? [String: Any], let m = e["message"] as? String {
                completion(.failure(AIError.api(m)))
            } else {
                completion(.failure(AIError.parse))
            }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Generate regex with AI").font(.headline)

            HStack(spacing: 6) {
                Group {
                    if showKey { TextField("OpenCode API key", text: $ai.apiKey) }
                    else { SecureField("OpenCode API key", text: $ai.apiKey) }
                }
                .textFieldStyle(.roundedBorder)
                Button { showKey.toggle() } label: { Image(systemName: showKey ? "eye.slash" : "eye") }
                    .buttonStyle(.borderless)
            }
            TextField("Model", text: $ai.model).textFieldStyle(.roundedBorder)

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
            Text("Calls OpenCode (\(ai.model)). Your key is stored locally on this Mac.")
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
