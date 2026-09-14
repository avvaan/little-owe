#if LITTLE_OWL_AI
import Foundation

/// The only code in this app that opens a network connection, and it is not in the app
/// unless somebody asked for it at build time.
///
/// Read `OwlBrain` first for why this exists at all. What is worth saying here is what
/// leaves the iPad and what does not:
///
/// - **Out** goes the question, as recognised text. Nothing else: no identifier, no
///   device information, no history, no previous question.
/// - **Not out** goes the audio. The child's voice is recognised on the device — the
///   app refuses to start a recognition task that is not on-device — and it is the text
///   that travels, the same text the caption would have shown.
/// - **Nothing comes back but a sentence,** and `OwlAnswerGuard` decides whether the
///   child hears it.
///
/// There is no session and no memory. Each question is a fresh request that knows
/// nothing of the last one, which is a smaller feature than a conversation and a much
/// smaller thing to have got wrong.
final class AnthropicOwlBrain: OwlBrain {

    /// Long enough for a sentence, short enough that a child asking a question does not
    /// watch a still owl. `WhyMode` hums through it either way, and a timeout lands on
    /// the ordinary "I do not know" line rather than on an error.
    static let timeout: TimeInterval = 8

    private let key: String
    private let model: String
    private let session: URLSession

    init(key: String, model: String = "claude-haiku-4-5-20251001") {
        self.key = key
        self.model = model

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = Self.timeout
        configuration.timeoutIntervalForResource = Self.timeout
        // Nothing about a child's questions belongs in a cache on disk.
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        session = URLSession(configuration: configuration)
    }

    func answer(to question: String) async -> String? {
        guard let request = makeRequest(question) else { return nil }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            guard let text = Self.firstText(in: data) else { return nil }
            return OwlAnswerGuard.clean(text)
        } catch {
            // A flat aeroplane-mode failure and a timeout are the same thing to a child:
            // the owl does not know this one. There is nowhere to report an error to and
            // nobody who would want one.
            return nil
        }
    }

    private func makeRequest(_ question: String) -> URLRequest? {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else { return nil }

        let body: [String: Any] = [
            "model": model,
            // The guard cuts to two sentences anyway; capping here means the model is
            // not paid to write the part that gets thrown away.
            "max_tokens": 150,
            "system": OwlPrompt.system,
            "messages": [["role": "user", "content": question]]
        ]
        guard let payload = try? JSONSerialization.data(withJSONObject: body) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = payload
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        return request
    }

    /// The first text block of the reply. Hand-parsed rather than modelled, because the
    /// only thing this app wants from that document is one string, and a `Decodable`
    /// tree of it would be five types that exist to be thrown away.
    static func firstText(in data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = object["content"] as? [[String: Any]] else { return nil }

        for block in content where block["type"] as? String == "text" {
            if let text = block["text"] as? String { return text }
        }
        return nil
    }
}
#endif
