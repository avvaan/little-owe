import Foundation

/// Pulling the sentence out of whatever JSON a provider sends back.
///
/// Always compiled, and separate from the code that makes the request, for one reason:
/// this is where the bugs are. Opening a socket is the part that either works or times
/// out; reading a document whose shape is decided by somebody else is the part that
/// quietly returns nil forever after they add a field. So the parsing is tested in
/// every build, including the ones with no networking in them at all.
///
/// Hand-parsed rather than modelled. The only thing this app wants from either document
/// is one string, and a `Decodable` tree of it would be five types that exist to be
/// thrown away — and would fail the whole parse on a field it did not expect, which is
/// the opposite of what is wanted here.
enum BrainReply {

    /// Anthropic's Messages API: `{"content": [{"type": "text", "text": "..."}]}`.
    ///
    /// A reply can carry more than one block and they are not all text, so this takes
    /// the first text one rather than the first one.
    static func fromAnthropic(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = object["content"] as? [[String: Any]] else { return nil }

        for block in content where block["type"] as? String == "text" {
            if let text = block["text"] as? String, !text.isEmpty { return text }
        }
        return nil
    }

    /// DeepSeek, which is OpenAI-shaped:
    /// `{"choices": [{"message": {"content": "..."}}]}`.
    ///
    /// A reasoning model puts its working in `reasoning_content` and its answer in
    /// `content`, and only `content` is read here. The owl says the answer; it does not
    /// think out loud at a five-year-old.
    static func fromDeepSeek(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = object["choices"] as? [[String: Any]] else { return nil }

        for choice in choices {
            guard let message = choice["message"] as? [String: Any],
                  let text = message["content"] as? String,
                  !text.isEmpty else { continue }
            return text
        }
        return nil
    }

    static func text(_ data: Data, from provider: BrainProvider) -> String? {
        switch provider {
        case .anthropic: return fromAnthropic(data)
        case .deepseek:  return fromDeepSeek(data)
        }
    }
}
