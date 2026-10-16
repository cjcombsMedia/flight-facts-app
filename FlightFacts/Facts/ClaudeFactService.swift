import Foundation

/// Optional online enrichment: asks Claude for a fact about wherever you are.
///
/// This is strictly a bonus layer. The bundled corpus carries the app; this
/// fills gaps over places nobody hand-wrote an entry for (most of Siberia, most
/// of the Pacific, most of the Sahara).
///
/// ⚠️ The key lives in the Keychain and goes straight from the device to the
/// API. That is fine for your own build. If this ever ships to other people,
/// move the call behind a server you control — a key embedded in a distributed
/// app is a key you have given away.
final class ClaudeFactService {

    struct Context {
        var lat: Double
        var lon: Double
        var altitudeM: Double
        var region: String?
        var country: String?
        var nearby: [String]
        var date: Date
    }

    private let session: URLSession
    private var inFlight: Task<Void, Never>?

    /// Claude Opus 5.5. Thinking is always on for this model, so `effort` is the
    /// only depth control — `low` suits a one-paragraph fact.
    var model = "claude-opus-5-5"
    var isEnabled: Bool { KeychainStore.apiKey?.isEmpty == false }

    init() {
        let config = URLSessionConfiguration.default
        // In the air, a request either works quickly or it is not going to.
        config.timeoutIntervalForRequest = 20
        config.waitsForConnectivity = false
        session = URLSession(configuration: config)
    }

    func cancel() {
        inFlight?.cancel()
        inFlight = nil
    }

    /// Requests one fact. Calls back on the main queue, or not at all on failure —
    /// there is no useful way to surface "the internet did not work at FL380".
    func fact(for context: Context, completion: @escaping (Bubble) -> Void) {
        guard let key = KeychainStore.apiKey, !key.isEmpty else { return }
        inFlight?.cancel()

        inFlight = Task { [weak self] in
            guard let self else { return }
            guard let bubble = await self.request(context: context, key: key) else { return }
            guard !Task.isCancelled else { return }
            await MainActor.run { completion(bubble) }
        }
    }

    private func request(context: Context, key: String) async -> Bubble? {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else { return nil }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        // Server-side fallback: if a safety classifier declines, the API retries
        // on an appropriate model instead of returning nothing.
        req.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")

        let payload: [String: Any] = [
            "model": model,
            // Thinking tokens count against this, so leave room beyond the
            // ~60-word answer — 400 could be spent entirely on thinking.
            "max_tokens": 4_000,
            "output_config": ["effort": "low"],
            "fallbacks": "default",
            "system": Self.systemPrompt,
            "messages": [["role": "user", "content": Self.userPrompt(context)]]
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }

            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  // Only a complete answer: not a refusal, not cut off at max_tokens.
                  root["stop_reason"] as? String == "end_turn",
                  let content = root["content"] as? [[String: Any]],
                  // Thinking blocks come first; take the text block.
                  let text = content.first(where: { $0["type"] as? String == "text" })?["text"] as? String
            else { return nil }

            return Self.parse(text)
        } catch {
            return nil
        }
    }

    // MARK: Prompting

    private static let systemPrompt = """
    You write short, surprising facts for passengers looking out of an airliner \
    window at 38,000 feet.

    Rules:
    - One fact only. Something a curious adult would not already know.
    - Prefer things that are visible or relevant from the air: geology, scale, \
      water, human infrastructure, aviation.
    - Never invent specifics. If you are not confident about a number, a date or \
      a name, leave it out and say something you are sure of.
    - No filler openings. No "did you know". No exclamation marks.

    Respond in exactly this format and nothing else:
    TITLE: <up to 6 words>
    BODY: <1-2 sentences, under 45 words>
    MORE: <one further sentence of detail>
    """

    private static func userPrompt(_ c: Context) -> String {
        var lines = [
            "Position: \(String(format: "%.3f", c.lat)), \(String(format: "%.3f", c.lon))",
            "Altitude: \(Int(c.altitudeM * 3.280839895)) ft"
        ]
        if let r = c.region { lines.append("Region: \(r)") }
        if let co = c.country { lines.append("Country: \(co)") }
        if !c.nearby.isEmpty {
            lines.append("Already mentioned (do not repeat): \(c.nearby.joined(separator: ", "))")
        }
        lines.append("Date: \(ISO8601DateFormatter().string(from: c.date))")
        lines.append("")
        lines.append("Give me one fact about what is below or around this position.")
        return lines.joined(separator: "\n")
    }

    private static func parse(_ text: String) -> Bubble? {
        var title = "", body = "", more = ""
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let s = line.trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("TITLE:") { title = String(s.dropFirst(6)).trimmingCharacters(in: .whitespaces) }
            else if s.hasPrefix("BODY:") { body = String(s.dropFirst(5)).trimmingCharacters(in: .whitespaces) }
            else if s.hasPrefix("MORE:") { more = String(s.dropFirst(5)).trimmingCharacters(in: .whitespaces) }
        }
        guard !title.isEmpty, !body.isEmpty else { return nil }
        return Bubble(kind: .ai, title: title, body: body,
                      detail: more.isEmpty ? [] : [more], priority: .low)
    }
}

/// Minimal Keychain wrapper for the API key. UserDefaults would be the wrong
/// place for a credential even in a personal build.
enum KeychainStore {

    private static let service = "com.cjcombs.flightfacts"
    private static let account = "anthropic-api-key"

    static var apiKey: String? {
        get {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]
            var item: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
                  let data = item as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        }
        set {
            let base: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
            ]
            SecItemDelete(base as CFDictionary)
            guard let value = newValue, !value.isEmpty,
                  let data = value.data(using: .utf8) else { return }
            var add = base
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(add as CFDictionary, nil)
        }
    }
}
