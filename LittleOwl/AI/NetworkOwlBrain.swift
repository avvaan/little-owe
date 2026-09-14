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
///
/// One type for both providers rather than two nearly identical ones: they differ in
/// three places — the URL, how the key is presented, and where the system prompt sits in
/// the body — and three differences side by side are easier to keep honest than two
/// files that drift.
final class NetworkOwlBrain: OwlBrain {

    /// Long enough for a sentence, short enough that a child asking a question does not
    /// watch a still owl. `WhyMode` hums through it either way, and a timeout lands on
    /// the ordinary "I do not know" line rather than on an error.
    static let timeout: TimeInterval = 8

    let provider: BrainProvider
    private let key: String
    private let model: String

    /// One session for the app rather than one per brain. A brain is now built fresh
    /// for each unanswered question — so that a parent who has just typed a key does
    /// not have to restart the app — and a new `URLSession` per question would be a
    /// connection pool per question.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = NetworkOwlBrain.timeout
        configuration.timeoutIntervalForResource = NetworkOwlBrain.timeout
        // Nothing about a child's questions belongs in a cache on disk.
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        return URLSession(configuration: configuration)
    }()

    /// The default model per provider. Both are the small fast one: this is one or two
    /// sentences for a five-year-old, not a reasoning problem, and a child waiting is a
    /// child who has wandered off.
    static func defaultModel(for provider: BrainProvider) -> String {
        switch provider {
        case .anthropic:
            return "claude-haiku-4-5-20251001"
        case .deepseek:
            // Not `deepseek-chat` or `deepseek-reasoner`: those two names were retired
            // on 2026-07-24 and a request naming them is refused. Checked against
            // DeepSeek's own change log rather than remembered.
            return "deepseek-v4-pro"
        }
    }

    init(provider: BrainProvider, key: String, model: String? = nil) {
        self.provider = provider
        self.key = key
        self.model = model ?? Self.defaultModel(for: provider)
    }

    func answer(to question: String) async -> String? {
        guard let request = makeRequest(question) else { return nil }

        do {
            let (data, response) = try await Self.session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            guard let text = BrainReply.text(data, from: provider) else { return nil }
            return OwlAnswerGuard.clean(text)
        } catch {
            // A flat aeroplane-mode failure and a timeout are the same thing to a child:
            // the owl does not know this one. There is nowhere to report an error to and
            // nobody who would want one.
            return nil
        }
    }

    // MARK: The three differences

    private var endpoint: URL? {
        switch provider {
        case .anthropic: return URL(string: "https://api.anthropic.com/v1/messages")
        case .deepseek:  return URL(string: "https://api.deepseek.com/v1/chat/completions")
        }
    }

    private func body(asking question: String) -> [String: Any] {
        // The guard cuts to two sentences anyway; capping here means the model is not
        // paid to write the part that gets thrown away.
        switch provider {
        case .anthropic:
            return [
                "model": model,
                "max_tokens": 150,
                "system": OwlPrompt.system,
                "messages": [["role": "user", "content": question]]
            ]
        case .deepseek:
            // OpenAI-shaped: the system prompt is a message rather than a field.
            return [
                "model": model,
                "max_tokens": 150,
                "messages": [
                    ["role": "system", "content": OwlPrompt.system],
                    ["role": "user", "content": question]
                ]
            ]
        }
    }

    private func authorise(_ request: inout URLRequest) {
        switch provider {
        case .anthropic:
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .deepseek:
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
    }

    // MARK: Building it

    private func makeRequest(_ question: String) -> URLRequest? {
        guard let endpoint else { return nil }
        guard let payload = try? JSONSerialization.data(withJSONObject: body(asking: question)) else {
            return nil
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = payload
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        authorise(&request)
        return request
    }
}
#endif
