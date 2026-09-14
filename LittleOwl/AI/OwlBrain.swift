import Foundation

/// The seam where an answer can come from somewhere other than the content pack.
///
/// Everything else in this app is a sentence somebody wrote. `WhyMode` says so in its
/// own doc comment and means it: the owl knows about a hundred and thirty things
/// children ask, and on a miss it says it does not know and sends them to a grown-up.
///
/// This is the one place that can change. It exists because the miss is the only dead
/// end in the app — a child who asks something real and gets "ask your grown-up" has
/// been turned away — and because this particular copy of the app has exactly one user,
/// whose parent is the person who built it.
///
/// **Three things keep it honest:**
///
/// - The whole implementation is behind `LITTLE_OWL_AI`. A build without that flag has
///   no networking code in it at all, which is what `docs/APP_STORE.md` claims and what
///   the App Store build must be. This is not a runtime switch pretending to be one.
/// - Nothing reaches the child unchecked. `OwlAnswerGuard` shapes and vets every
///   answer, and anything it rejects becomes the ordinary "I do not know" line — so the
///   worst case is the behaviour the app already had.
/// - There is no conversation and no memory. One question in, one answer out, nothing
///   kept. The owl cannot be talked into anything over five turns because there are
///   never five turns.
protocol OwlBrain: AnyObject {
    /// Answers a child's question, or returns nil if it cannot — including when it
    /// simply should not. A nil is not an error to report; it is the owl saying it does
    /// not know, which it is allowed to do.
    func answer(to question: String) async -> String?
}

/// Who the owl asks.
///
/// Always compiled, even in a build with no networking, so the settings screen and the
/// stored preference are the same code everywhere and only the asking is conditional.
///
/// The choice is the parent's rather than the architecture's. They are not equivalent:
/// the whole of what keeps this safe for a five-year-old is how well a model follows
/// "do not answer that one at all", and models differ at it. So the screen says where
/// each one sends the question, and the parent decides.
enum BrainProvider: String, CaseIterable, Identifiable {
    case anthropic
    case deepseek

    var id: String { rawValue }

    var name: String {
        switch self {
        case .anthropic: return "Claude"
        case .deepseek:  return "DeepSeek"
        }
    }

    /// Where the question goes. Said plainly, because a parent choosing this for their
    /// own child is entitled to know it without reading the source.
    var destination: String {
        switch self {
        case .anthropic: return "Anthropic, in the United States"
        case .deepseek:  return "DeepSeek, in China"
        }
    }

    var keyPrompt: String {
        switch self {
        case .anthropic: return "Anthropic API key"
        case .deepseek:  return "DeepSeek API key"
        }
    }
}

/// What the owl is told it is.
///
/// Kept here rather than next to the networking so it is readable in a build that has
/// no networking, and so a change to it is a change somebody reviews.
enum OwlPrompt {
    static let system = """
        You are a small, kind owl who lives in a cosy attic and is talking to a five-year-old child.

        Answer the child's question in one or two short sentences. Use the words a \
        five-year-old knows. If a word is too big, use a smaller one, or explain it in \
        the same breath.

        Be warm and a little playful, the way a favourite toy is. Never lecture.

        If the true answer is frightening, sad, or about death, violence, illness, sex, \
        money worries, or anything else a grown-up should be the one to say, do not \
        answer it. Reply with exactly: I do not know that one. Ask your grown-up.

        If you do not know, say exactly the same thing rather than guessing. A child \
        believes you.

        Never mention that you are a computer, a model, or an assistant. You are an owl.
        Never ask the child for their name, where they live, or anything else about them.
        Write plain spoken sentences only: no lists, no headings, no asterisks, no links, \
        no emoji. What you write is read aloud.
        """

    /// The exact sentence the prompt asks for when the owl should not answer, so the
    /// guard can recognise it and hand the mode its own written line instead — the one
    /// the child already knows the sound of.
    static let declined = "I do not know that one. Ask your grown-up."
}
