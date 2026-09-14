import Foundation

/// One language's content, loaded from `content/<language>/` in the bundle.
///
/// Nothing in the code names a language. A second pack is a sibling folder with the
/// same six files and its own `pack.json`; `ContentLoader` finds it by looking, and the
/// modes above never learn which one they got.
struct ContentPack {

    let language: String
    let displayName: String

    /// Which `AVSpeechSynthesizer` voice stands in for a line that has no recording.
    let speechLocale: String
    /// Which locale `SFSpeechRecognizer` is asked for.
    let recognitionLocale: String

    let heroes: [Hero]
    let stories: [Story]
    let spokenSets: [SpokenSet]
    let wordGames: [WordGame]
    let questions: [Question]
    let phrases: [PhraseGroup: [Phrase]]

    // MARK: Lookup

    func stories(for heroID: String) -> [Story] {
        stories.filter { $0.heroID == heroID }
    }

    func sets(of kind: SpokenSet.Kind) -> [SpokenSet] {
        spokenSets.filter { $0.kind == kind }
    }

    func hero(_ id: String) -> Hero? {
        heroes.first { $0.id == id }
    }

    /// A random line from a group. Returns nil only if the pack has none, which the
    /// loader treats as a broken pack rather than something to paper over at runtime.
    func phrase(_ group: PhraseGroup) -> Phrase? {
        phrases[group]?.randomElement()
    }
}

// MARK: - Anything the owl can say

/// Every spoken thing carries the same three fields the brief asks for: an id, the
/// text, and the audio that goes with it.
///
/// The filename is a convention rather than a field: `audioName` is derived from the
/// item's identity, so a voice actor's delivery drops into `content/<lang>/audio/`
/// without anybody editing JSON, and a missing file simply falls back to the
/// synthesiser. An explicit `audioOverride` exists for the odd line that needs it.
protocol Speakable {
    var id: String { get }
    var text: String { get }
    var audioOverride: String? { get }
    /// Conventional filename, without the extension.
    var audioStem: String { get }
}

extension Speakable {
    var audioName: String { audioOverride ?? audioStem }
}

/// A spoken line assembled in code rather than decoded — a word game's prompt, a
/// question's answer. The JSON keeps those as plain strings so it stays readable.
struct SpokenText: Speakable, Equatable {
    let id: String
    let text: String
    let audioOverride: String? = nil
    let audioStem: String

    init(id: String, text: String, stem: String) {
        self.id = id
        self.text = text
        self.audioStem = stem
    }
}

// MARK: - Stories

struct Hero: Decodable, Equatable {
    let id: String
    let name: String
    /// Illustration filename. Stories mode draws a card in `colour` until it exists.
    let card: String?
    /// Six-digit hex, for the placeholder card and the page tint.
    let colour: String?
    let tags: [String]

    enum CodingKeys: String, CodingKey { case id, name, card, colour, tags }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        card = try c.decodeIfPresent(String.self, forKey: .card)
        colour = try c.decodeIfPresent(String.self, forKey: .colour)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
    }
}

struct Story: Decodable, Equatable {
    let id: String
    let heroID: String
    /// Parent-facing only. The child picks a hero, never a title.
    let title: String
    let pages: [Page]
    let tags: [String]

    struct Page: Decodable, Equatable, Speakable {
        let id: String
        let text: String
        let illustration: String?
        let audioOverride: String?

        /// Set by `Story` after decoding, so a page knows its own audio name.
        fileprivate(set) var audioStem: String = ""

        enum CodingKeys: String, CodingKey { case id, text, illustration, audio }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            text = try c.decode(String.self, forKey: .text)
            illustration = try c.decodeIfPresent(String.self, forKey: .illustration)
            audioOverride = try c.decodeIfPresent(String.self, forKey: .audio)
        }
    }

    enum CodingKeys: String, CodingKey { case id, heroId, title, pages, tags }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        heroID = try c.decode(String.self, forKey: .heroId)
        title = try c.decode(String.self, forKey: .title)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []

        let storyID = id
        pages = try c.decode([Page].self, forKey: .pages).map { page in
            var page = page
            page.audioStem = "story_\(storyID)_\(page.id)"
            return page
        }
    }
}

// MARK: - Prayers and rhymes

struct SpokenSet: Decodable, Equatable {

    enum Kind: String, Decodable {
        case prayer
        case rhyme
    }

    let id: String
    let kind: Kind
    /// Shown in parent settings only.
    let title: String
    /// What the child taps to choose this set: a name from `SetSymbol`, drawn on the
    /// card. It is the whole label — a three-year-old cannot read "Before meals", so the
    /// bowl is not decoration.
    let symbol: String
    /// Six hex digits for the card behind the symbol.
    let colour: String?

    /// The painting on this set's card, by convention rather than by a field in the
    /// JSON — `set_prayer-morning.png`. Derived for the same reason the audio stem is:
    /// a name written down twice is a name that drifts, and a card whose painting has
    /// not arrived falls back to its symbol rather than to nothing. No extension: what
    /// ships is a JPEG and `ContentLoader` asks the bundle rather than guessing.
    var illustration: String { "set_\(id)" }
    /// True while the text is standing in for one the family will supply.
    let isPlaceholder: Bool
    let source: String?
    let lines: [Line]
    let tags: [String]

    struct Line: Decodable, Equatable, Speakable {
        let id: String
        let text: String
        let audioOverride: String?
        fileprivate(set) var audioStem: String = ""

        enum CodingKeys: String, CodingKey { case id, text, audio }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            text = try c.decode(String.self, forKey: .text)
            audioOverride = try c.decodeIfPresent(String.self, forKey: .audio)
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, title, symbol, colour, placeholder, source, lines, tags
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = try c.decode(Kind.self, forKey: .kind)
        title = try c.decode(String.self, forKey: .title)
        // A set with no symbol still gets a card rather than a blank one; a test keeps
        // the shipped pack from relying on that.
        symbol = try c.decodeIfPresent(String.self, forKey: .symbol) ?? "star"
        colour = try c.decodeIfPresent(String.self, forKey: .colour)
        isPlaceholder = try c.decodeIfPresent(Bool.self, forKey: .placeholder) ?? false
        source = try c.decodeIfPresent(String.self, forKey: .source)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []

        let setID = id
        lines = try c.decode([Line].self, forKey: .lines).map { line in
            var line = line
            line.audioStem = "set_\(setID)_\(line.id)"
            return line
        }
    }
}

// MARK: - Word games

struct WordGame: Decodable, Equatable {

    enum Kind: String, Decodable {
        case nameOne
        case oddOneOut
        case animalSound
        case counting
    }

    let id: String
    let kind: Kind
    /// What the owl asks.
    let prompt: String
    /// Answers the child may say. Matched loosely — see `AnswerMatcher`.
    let accepted: [String]
    /// What the owl offers when the answer was not on the list. It never says wrong.
    let reveal: String
    /// Pictures for the no-recognition path. The first is the correct one; the mode
    /// shuffles them before showing.
    let choices: [String]
    let tags: [String]

    var promptLine: SpokenText { SpokenText(id: id, text: prompt, stem: "game_\(id)_prompt") }
    var revealLine: SpokenText { SpokenText(id: id, text: reveal, stem: "game_\(id)_reveal") }

    enum CodingKeys: String, CodingKey { case id, kind, prompt, accepted, reveal, choices, tags }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = try c.decode(Kind.self, forKey: .kind)
        prompt = try c.decode(String.self, forKey: .prompt)
        accepted = try c.decode([String].self, forKey: .accepted)
        reveal = try c.decode(String.self, forKey: .reveal)
        choices = try c.decodeIfPresent([String].self, forKey: .choices) ?? []
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
    }
}

// MARK: - Why questions

struct Question: Decodable, Equatable {
    let id: String
    /// The canonical phrasing, for the parent-facing list and for tests.
    let text: String
    /// Words that must mostly be present in what the child said. Nouns, not question words.
    let keywords: [String]
    /// Whole phrasings that should also hit.
    let alternates: [String]
    let answer: String
    let tags: [String]

    /// What the owl actually says. `text` is only the phrasing that matched.
    var answerLine: SpokenText { SpokenText(id: id, text: answer, stem: "question_\(id)") }

    enum CodingKeys: String, CodingKey { case id, text, keywords, alternates, answer, tags }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        text = try c.decode(String.self, forKey: .text)
        keywords = try c.decode([String].self, forKey: .keywords)
        alternates = try c.decodeIfPresent([String].self, forKey: .alternates) ?? []
        answer = try c.decode(String.self, forKey: .answer)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
    }

}

// MARK: - The owl's stock lines

enum PhraseGroup: String, CaseIterable {
    case praise
    case kindTry
    case nudge
    case unknownQuestion
    case storyAgain
    /// Said once at the top of a prayer or rhyme: the only explanation a child gets of
    /// what the mode is, and it has to be spoken rather than written.
    case repeatInvite
    /// Offered when a set is finished and the lamp is glowing.
    case setAgain
    /// The owl asking the child to ask it something, at the window.
    case askInvite
    /// Said before the tap-to-choose cards on a device that cannot hear.
    case chooseInvite
}

struct Phrase: Decodable, Equatable, Speakable {
    let id: String
    let text: String
    let audioOverride: String?
    var audioStem: String { "phrase_\(id)" }

    enum CodingKeys: String, CodingKey { case id, text, audio }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        text = try c.decode(String.self, forKey: .text)
        audioOverride = try c.decodeIfPresent(String.self, forKey: .audio)
    }
}
