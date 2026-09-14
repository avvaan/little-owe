import Foundation

/// Did the child say the line back?
///
/// Deliberately not a grader. The brief is explicit: recognition is used only to detect
/// *that the child said something of roughly the right length*, never whether they said
/// it correctly, and the owl never says "wrong". So this counts words and nothing else —
/// not which words, not their order, not how they were heard. A child who answers
/// "twinkle star" to "Twinkle, twinkle, little star," has said it.
///
/// It exists as a separate, pure type because it is the one piece of Prayers that can be
/// reasoned about without a microphone, and because the numbers in it are the difference
/// between an owl that waits patiently and an owl that quietly grades a three-year-old.
enum RepeatJudge {

    enum Outcome: Equatable {
        /// Enough came back. The owl praises and moves on.
        case repeated
        /// Not enough, or nothing at all. The owl says the line again — gently, once.
        case notEnough
    }

    /// What share of a line counts as having said it. Low on purpose: a three-year-old
    /// repeating a rhyme gets a fragment of it out, and asking for more would be grading.
    static let share = 0.35

    /// However long the line, this many words is always enough. A ten-word line asks for
    /// four words, not seven — long lines are the ones a small child most needs help
    /// with, so they must not be the hardest to pass.
    static let cap = 4

    static func wordCount(of text: String) -> Int {
        OwlVoice.wordRanges(in: text).count
    }

    static func requiredWords(forLineOf words: Int) -> Int {
        guard words > 0 else { return 1 }
        return max(1, min(cap, Int((Double(words) * share).rounded())))
    }

    /// `heard` is nil when nothing was recognised.
    static func judge(line: String, heard: String?) -> Outcome {
        guard let heard, !heard.isEmpty else { return .notEnough }
        let needed = requiredWords(forLineOf: wordCount(of: line))
        return wordCount(of: heard) >= needed ? .repeated : .notEnough
    }

    /// How long the owl waits when it cannot hear at all — no recogniser on the device,
    /// or no microphone permission yet.
    ///
    /// The brief calls this "a fixed pause". It is fixed in the sense that matters —
    /// nothing is being measured and nothing can fail — but it is scaled to the line,
    /// because four seconds of silence after "We give our thanks." is a very different
    /// pause from four seconds after a ten-word one.
    static func fallbackPause(forLineOf words: Int) -> TimeInterval {
        min(9.0, max(2.5, 1.2 + 0.55 * Double(words)))
    }
}
