import Foundation

/// Finds and reads the content packs shipped in the bundle.
///
/// Packs live in `content/<language>/`, added to the target as a folder reference so
/// the directory structure survives into the bundle. Adding a language is dropping a
/// sibling folder next to `en`: no code changes, no registration, nothing to rebuild
/// but the app.
enum ContentLoader {

    enum Failure: Error, CustomStringConvertible {
        case noContentFolder
        case noPacks
        case missingFile(language: String, file: String)
        case unreadable(language: String, file: String, underlying: Error)

        var description: String {
            switch self {
            case .noContentFolder:
                return "The bundle has no content/ folder. It is a folder reference in the Resources build phase — check it is still there."
            case .noPacks:
                return "content/ exists but holds no language folder with a pack.json."
            case .missingFile(let language, let file):
                return "content/\(language)/\(file) is missing."
            case .unreadable(let language, let file, let underlying):
                return "content/\(language)/\(file) could not be read: \(underlying)"
            }
        }
    }

    /// Language codes with a readable `pack.json`, sorted so the order is stable.
    static func availableLanguages(in bundle: Bundle = .main) throws -> [String] {
        guard let root = contentRoot(in: bundle) else { throw Failure.noContentFolder }

        let folders = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        let languages = folders
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("pack.json").path) }
            .map(\.lastPathComponent)
            .sorted()

        guard !languages.isEmpty else { throw Failure.noPacks }
        return languages
    }

    /// Loads the pack for `language`, or the first available one when it is nil.
    static func load(language requested: String? = nil, from bundle: Bundle = .main) throws -> ContentPack {
        let languages = try availableLanguages(in: bundle)
        let language = requested.flatMap { languages.contains($0) ? $0 : nil } ?? languages[0]

        guard let root = contentRoot(in: bundle) else { throw Failure.noContentFolder }
        let folder = root.appendingPathComponent(language, isDirectory: true)

        let manifest: Manifest = try read(Manifest.self, "pack.json", in: folder, language: language)

        let heroes: HeroFile = try read(HeroFile.self, manifest.files.heroes, in: folder, language: language)
        let stories: StoryFile = try read(StoryFile.self, manifest.files.stories, in: folder, language: language)
        let sets: SpokenSetFile = try read(SpokenSetFile.self, manifest.files.spokenSets, in: folder, language: language)
        let games: WordGameFile = try read(WordGameFile.self, manifest.files.wordGames, in: folder, language: language)
        let questions: QuestionFile = try read(QuestionFile.self, manifest.files.questions, in: folder, language: language)
        let phrases: PhraseFile = try read(PhraseFile.self, manifest.files.phrases ?? "phrases.json", in: folder, language: language)

        return ContentPack(
            language: manifest.language,
            displayName: manifest.displayName,
            speechLocale: manifest.speechLocale,
            recognitionLocale: manifest.recognitionLocale,
            heroes: heroes.heroes,
            stories: stories.stories,
            spokenSets: sets.sets,
            wordGames: games.games,
            questions: questions.questions,
            phrases: phrases.groups
        )
    }

    /// Where a line's recording lives, if it has been delivered. Nil means the
    /// synthesiser stands in — which is the normal state until the voice actor records.
    static func audioURL(for speakable: any Speakable, language: String, in bundle: Bundle = .main) -> URL? {
        guard let root = contentRoot(in: bundle) else { return nil }
        // A line assembled at runtime has no stem and never will - a generated answer
        // cannot have been recorded. Without this, the lookup asks for a file called
        // ".m4a", which is a hidden file somebody could plausibly create by accident.
        guard !speakable.audioName.isEmpty else { return nil }

        let folder = root
            .appendingPathComponent(language, isDirectory: true)
            .appendingPathComponent("audio", isDirectory: true)

        for ext in ["m4a", "caf", "wav", "mp3"] {
            let url = folder.appendingPathComponent("\(speakable.audioName).\(ext)")
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    /// Where a picture lives, whatever it was saved as.
    ///
    /// The extension in the name is a hint, not a fact: the content pack says
    /// `fox_mitten_1.png` and what ships is a JPEG, because these are painted scenes
    /// with no transparency and PNG costs twenty times the bytes for no visible gain.
    /// Guessing an extension is what drew the whole room as a red cross once already,
    /// so this asks the bundle instead.
    static func illustrationURL(named name: String, language: String, in bundle: Bundle = .main) -> URL? {
        guard let root = contentRoot(in: bundle) else { return nil }
        let stem = (name as NSString).deletingPathExtension
        guard !stem.isEmpty else { return nil }

        let folder = root
            .appendingPathComponent(language, isDirectory: true)
            .appendingPathComponent("illustrations", isDirectory: true)

        for ext in ["jpg", "png", "jpeg", "webp"] {
            let url = folder.appendingPathComponent("\(stem).\(ext)")
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    // MARK: Internals

    private static func contentRoot(in bundle: Bundle) -> URL? {
        bundle.url(forResource: "content", withExtension: nil)
    }

    private static func read<T: Decodable>(
        _ type: T.Type, _ file: String, in folder: URL, language: String
    ) throws -> T {
        let url = folder.appendingPathComponent(file)
        guard let data = try? Data(contentsOf: url) else {
            throw Failure.missingFile(language: language, file: file)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw Failure.unreadable(language: language, file: file, underlying: error)
        }
    }
}

// MARK: - File shapes
//
// Each content file is an object with one array in it rather than a bare array, so a
// file can gain a sibling key later without breaking older builds. The `_comment` keys
// the files carry for translators are simply not decoded.

private struct Manifest: Decodable {
    struct Files: Decodable {
        let heroes: String
        let stories: String
        let spokenSets: String
        let wordGames: String
        let questions: String
        let phrases: String?
    }

    let schemaVersion: Int
    let language: String
    let displayName: String
    let speechLocale: String
    let recognitionLocale: String
    let files: Files
}

private struct HeroFile: Decodable { let heroes: [Hero] }
private struct StoryFile: Decodable { let stories: [Story] }
private struct SpokenSetFile: Decodable { let sets: [SpokenSet] }
private struct WordGameFile: Decodable { let games: [WordGame] }
private struct QuestionFile: Decodable { let questions: [Question] }

/// The phrases file mixes `_comment_*` strings in among the groups so a translator can
/// read what each one is for. Unknown keys are skipped rather than failing the decode,
/// and anything that is not a list of phrases is simply not a group.
private struct PhraseFile: Decodable {
    let groups: [PhraseGroup: [Phrase]]

    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    private enum Outer: String, CodingKey { case groups }

    init(from decoder: Decoder) throws {
        let outer = try decoder.container(keyedBy: Outer.self)
        let inner = try outer.nestedContainer(keyedBy: Key.self, forKey: .groups)

        var found: [PhraseGroup: [Phrase]] = [:]
        for key in inner.allKeys {
            guard !key.stringValue.hasPrefix("_"),
                  let group = PhraseGroup(rawValue: key.stringValue),
                  let phrases = try? inner.decode([Phrase].self, forKey: key) else { continue }
            found[group] = phrases
        }
        groups = found
    }
}
