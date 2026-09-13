import Foundation

/// Turning what the recogniser heard into something that can be compared with authored
/// content.
///
/// On-device recognition of a three-year-old is rough. It drops words, mishears
/// endings and never punctuates, so matching has to be forgiving in the ways that do
/// not change meaning — case, punctuation, plurals, the little words — and strict about
/// the ones that do.
enum SpeechMatching {

    /// Words carrying no meaning for matching. Deliberately only function words:
    /// dropping a verb like "come" would gut `Where does rain come from`.
    static let ignored: Set<String> = [
        "a", "an", "the", "is", "are", "am", "was", "were", "be", "been", "being",
        "do", "does", "did", "doing",
        "why", "what", "where", "when", "how", "who", "whose", "which",
        "to", "of", "in", "on", "at", "by", "from", "with", "for", "about",
        "it", "its", "i", "me", "my", "you", "your", "we", "us", "our",
        "he", "she", "his", "her", "they", "them", "their",
        "and", "or", "but", "so", "if", "then", "than",
        "that", "this", "these", "those", "there", "here",
        "have", "has", "had", "can", "could", "will", "would", "should",
        "just", "some", "any", "please", "tell"
    ]

    /// Lowercased, unpunctuated, de-pluralised words, with the function words dropped.
    static func tokens(_ text: String) -> [String] {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .map(singular)
            .filter { !ignored.contains($0) }
    }

    /// Plural-s only. Anything cleverer starts mangling words a child actually said.
    static func singular(_ word: String) -> String {
        guard word.count > 3, word.hasSuffix("s"), !word.hasSuffix("ss"), !word.hasSuffix("us") else {
            return word
        }
        if word.hasSuffix("ies"), word.count > 4 {
            return String(word.dropLast(3)) + "y"
        }
        if word.hasSuffix("es"), word.count > 4, "sxzo".contains(word[word.index(word.endIndex, offsetBy: -3)]) {
            return String(word.dropLast(2))
        }
        return String(word.dropLast())
    }
}

// MARK: - Word games

/// Whether what the child said counts as one of a task's accepted answers.
///
/// There is no "wrong" in this app: a false negative costs the child a small
/// disappointment and the owl moves on kindly either way, so the bar is set low on
/// purpose.
enum AnswerMatcher {

    static func accepts(heard: String, anyOf accepted: [String]) -> Bool {
        matched(heard: heard, anyOf: accepted) != nil
    }

    /// Which accepted answer was heard, if any. Useful for tests and for logging
    /// nothing at all in production.
    static func matched(heard: String, anyOf accepted: [String]) -> String? {
        let heardTokens = Set(SpeechMatching.tokens(heard))
        guard !heardTokens.isEmpty else { return nil }

        // Longest first: "the chair" should win over "chair" when both are listed.
        return accepted
            .sorted { SpeechMatching.tokens($0).count > SpeechMatching.tokens($1).count }
            .first { answer in
                let wanted = SpeechMatching.tokens(answer)
                return !wanted.isEmpty && wanted.allSatisfy(heardTokens.contains)
            }
    }
}

// MARK: - Why questions

/// Picks the question from the bank that best fits what the child asked, or nothing.
///
/// Nothing is generated: a miss means the owl says so and sends the child to a
/// grown-up. That is a feature of the brief, not a shortfall — an owl that invents
/// answers for a five-year-old is worse than one that admits it does not know.
struct QuestionMatcher {

    /// How much of a question's keyword set must be present. Two of three is enough;
    /// one of two is not.
    static let threshold = 0.6

    let questions: [Question]

    init(_ questions: [Question]) {
        self.questions = questions
    }

    struct Match {
        let question: Question
        let score: Double
        let matchedTokens: Int
    }

    func bestMatch(for heard: String) -> Match? {
        let heardTokens = Set(SpeechMatching.tokens(heard))
        guard !heardTokens.isEmpty else { return nil }

        var best: Match?
        for question in questions {
            guard let scored = score(question, against: heardTokens) else { continue }
            guard scored.score >= Self.threshold, scored.matchedTokens >= 1 else { continue }

            if let current = best {
                // A better fit wins; on a tie the more specific question does, because
                // it asked for more words and got them.
                let better = (scored.score, scored.matchedTokens) > (current.score, current.matchedTokens)
                if better { best = scored }
            } else {
                best = scored
            }
        }
        return best
    }

    func question(for heard: String) -> Question? {
        bestMatch(for: heard)?.question
    }

    private func score(_ question: Question, against heard: Set<String>) -> Match? {
        // The keyword list and each authored alternate are all candidate phrasings; the
        // question scores as well as its best one.
        var candidates: [[String]] = [question.keywords.flatMap(SpeechMatching.tokens)]
        candidates += question.alternates.map(SpeechMatching.tokens)

        var bestScore = 0.0
        var bestMatched = 0
        for candidate in candidates where !candidate.isEmpty {
            let hits = candidate.filter(heard.contains).count
            let score = Double(hits) / Double(candidate.count)
            if (score, hits) > (bestScore, bestMatched) {
                bestScore = score
                bestMatched = hits
            }
        }
        guard bestMatched > 0 else { return nil }
        return Match(question: question, score: bestScore, matchedTokens: bestMatched)
    }
}
