import Foundation

/// The last thing between a generated sentence and a five-year-old's ears.
///
/// It is deliberately not a content filter. A list of forbidden words would be easy to
/// write, easy to get round, and worst of all would feel like safety — so what actually
/// keeps this owl's mouth clean is the system prompt, the fact that the key belongs to
/// the child's own parent, and the fact that no build anybody else can install has this
/// code in it at all.
///
/// What this *does* do is refuse anything that is not a plain spoken answer. That covers
/// the failure modes a language model actually has here: a model that starts explaining
/// what it is, one that writes a bulleted list to a child who cannot read, one that
/// pastes a link, one that answers at the length of an encyclopaedia entry, and one that
/// declines — which should sound like the owl declining, not like software refusing.
///
/// Everything it rejects becomes the mode's ordinary "I do not know" line, so the worst
/// case is exactly the behaviour the app had before any of this existed.
enum OwlAnswerGuard {

    /// Two short sentences for a five-year-old. Past this the model has ignored the
    /// prompt, and whatever else it ignored is not worth finding out by playing it.
    static let maxCharacters = 260

    /// A child listening, not reading, so at most two sentences before their attention
    /// is somewhere else entirely.
    static let maxSentences = 2

    /// Shapes an answer for speaking, or returns nil if the owl should say it does not
    /// know instead.
    static func clean(_ raw: String) -> String? {
        // Newlines and runs of spaces are read by the synthesiser as pauses, and a pause
        // in the wrong place sounds like the owl faltering.
        let flattened = raw
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard !flattened.isEmpty else { return nil }
        guard !isFormatted(flattened) else { return nil }
        guard !isMeta(flattened) else { return nil }
        guard !declines(flattened) else { return nil }

        let trimmed = firstSentences(of: flattened)
        guard !trimmed.isEmpty, trimmed.count <= maxCharacters else { return nil }

        // A single word is not an answer to "why", whatever else it is.
        guard trimmed.split(separator: " ").count >= 3 else { return nil }

        return trimmed
    }

    /// Anything written to be read rather than heard.
    ///
    /// The list is short on purpose. A dash and a full stop after a digit both turn up
    /// in ordinary speech — "it is blue - mostly", "one and a half" written as 1.5 — and
    /// rejecting those would mean the owl shrugging at perfectly good answers. What is
    /// here cannot appear in a sentence somebody would say out loud.
    static func isFormatted(_ text: String) -> Bool {
        let anywhere = ["http://", "https://", "www.", "```", "<", "|", "* ", "**", "__", "#"]
        let lowered = text.lowercased()
        if anywhere.contains(where: lowered.contains) { return true }

        // A list marker is only a list marker at the front. Mid-sentence it is a dash.
        let starts = ["- ", "* ", "1. ", "1) ", "• "]
        if starts.contains(where: text.hasPrefix) { return true }

        // Emoji and the rest of the pictographs: nothing to read aloud.
        return text.unicodeScalars.contains { $0.properties.isEmojiPresentation }
    }

    /// The owl is an owl. A sentence that breaks that is worse than no sentence.
    static func isMeta(_ text: String) -> Bool {
        let tells = ["as an ai", "as a language model", "i am an ai", "i'm an ai",
                     "language model", "i am a computer", "i'm a computer",
                     "as an assistant", "i am an assistant", "i'm an assistant",
                     "my training", "my guidelines", "i was trained"]
        let lowered = text.lowercased()
        return tells.contains(where: lowered.contains)
    }

    /// The model doing as the prompt asked and standing down. The mode has its own
    /// written line for this, recorded in the owl's voice — better than reading the
    /// prompt's wording aloud in a synthesised one.
    static func declines(_ text: String) -> Bool {
        let lowered = text.lowercased()
        let tells = ["i do not know that one", "i don't know that one",
                     "ask your grown-up", "ask your grownup", "i cannot answer",
                     "i can't answer", "i am not able to", "i'm not able to"]
        return tells.contains(where: lowered.contains)
    }

    /// The first sentences, terminator included. Splitting on the terminator rather than
    /// counting characters means a cut-off answer never ends mid-word.
    static func firstSentences(of text: String) -> String {
        var kept: [String] = []
        var current = ""
        let characters = Array(text)

        for (index, character) in characters.enumerated() {
            current.append(character)
            guard character == "." || character == "!" || character == "?" else { continue }

            // A full stop with something other than a space hard after it is a decimal
            // point or an abbreviation, not the end of a sentence. Without this, "it
            // takes about 1.5 seconds" is read to a child as "it takes about one. Five
            // seconds."
            let next = index + 1 < characters.count ? characters[index + 1] : " "
            guard next == " " else { continue }

            kept.append(current.trimmingCharacters(in: .whitespaces))
            current = ""
            if kept.count == maxSentences { break }
        }

        if kept.isEmpty {
            // No terminator at all: one unfinished sentence, which is what a model
            // truncated by a token limit produces. Not something to read to a child.
            return ""
        }

        return kept.joined(separator: " ")
    }
}
