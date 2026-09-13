import XCTest
@testable import LittleOwl

/// The schema is the contract with whoever writes the content and whoever translates
/// it. These tests are mostly about that contract holding, not about Swift.
final class ContentPackTests: XCTestCase {

    // MARK: Decoding

    func testStoryPagesLearnTheirAudioName() {
        let story = decode(Story.self, [
            "id": "fox-mitten", "heroId": "fox", "title": "The Lost Mitten",
            "pages": [["id": "p1", "text": "Once."], ["id": "p2", "text": "Twice."]]
        ])

        XCTAssertEqual(story.pages.map(\.audioName), ["story_fox-mitten_p1", "story_fox-mitten_p2"])
    }

    func testAnExplicitAudioNameWins() {
        let story = decode(Story.self, [
            "id": "s", "heroId": "h", "title": "T",
            "pages": [["id": "p1", "text": "Once.", "audio": "special_take_3"]]
        ])

        XCTAssertEqual(story.pages[0].audioName, "special_take_3")
    }

    func testSpokenSetLinesLearnTheirAudioName() {
        let set = decode(SpokenSet.self, [
            "id": "rhyme-twinkle", "kind": "rhyme", "title": "Twinkle",
            "lines": [["id": "l1", "text": "Twinkle, twinkle."]]
        ])

        XCTAssertEqual(set.lines[0].audioName, "set_rhyme-twinkle_l1")
        XCTAssertEqual(set.kind, .rhyme)
        XCTAssertFalse(set.isPlaceholder)
    }

    func testWordGameSplitsIntoTwoSpokenHalves() {
        let game = decode(WordGame.self, [
            "id": "animal-m", "kind": "nameOne",
            "prompt": "Name an animal starting with M.",
            "accepted": ["monkey"], "reveal": "A monkey!"
        ])

        XCTAssertEqual(game.promptLine.audioName, "game_animal-m_prompt")
        XCTAssertEqual(game.revealLine.audioName, "game_animal-m_reveal")
        XCTAssertEqual(game.revealLine.text, "A monkey!")
        XCTAssertTrue(game.choices.isEmpty, "choices is optional and defaults to empty")
    }

    func testOptionalFieldsHaveSaneDefaults() {
        let hero = decode(Hero.self, ["id": "fox", "name": "Fern"])
        XCTAssertTrue(hero.tags.isEmpty)
        XCTAssertNil(hero.card)
    }

    // MARK: The shipped pack

    func testTheShippedPackLoads() throws {
        let pack = try ContentPack.shipped()
        XCTAssertEqual(pack.language, "en")
        XCTAssertFalse(pack.heroes.isEmpty)
        XCTAssertFalse(pack.stories.isEmpty)
        XCTAssertFalse(pack.wordGames.isEmpty)
        XCTAssertFalse(pack.questions.isEmpty)
    }

    func testEnglishIsAmongTheAvailableLanguages() throws {
        XCTAssertTrue(try ContentLoader.availableLanguages().contains("en"))
    }

    func testEveryStoryPointsAtAHeroThatExists() throws {
        let pack = try ContentPack.shipped()
        let heroes = Set(pack.heroes.map(\.id))

        for story in pack.stories {
            XCTAssertTrue(heroes.contains(story.heroID),
                          "story \(story.id) names hero \(story.heroID), which is not in heroes.json")
        }
    }

    func testEveryHeroHasAtLeastOneStory() throws {
        let pack = try ContentPack.shipped()
        for hero in pack.heroes {
            XCTAssertFalse(pack.stories(for: hero.id).isEmpty,
                           "hero \(hero.id) has no story, so its card would open onto nothing")
        }
    }

    func testIdentifiersAreUnique() throws {
        let pack = try ContentPack.shipped()

        func assertUnique(_ ids: [String], _ what: String) {
            XCTAssertEqual(Set(ids).count, ids.count, "duplicate \(what) id")
        }
        assertUnique(pack.heroes.map(\.id), "hero")
        assertUnique(pack.stories.map(\.id), "story")
        assertUnique(pack.spokenSets.map(\.id), "spoken set")
        assertUnique(pack.wordGames.map(\.id), "word game")
        assertUnique(pack.questions.map(\.id), "question")

        for story in pack.stories {
            assertUnique(story.pages.map(\.id), "page in \(story.id)")
        }
    }

    func testAudioNamesAreUniqueAcrossTheWholePack() throws {
        // Recordings all land in one folder, so a collision would silently give two
        // different lines the same take.
        let pack = try ContentPack.shipped()
        var names: [String] = []
        names += pack.stories.flatMap { $0.pages.map(\.audioName) }
        names += pack.spokenSets.flatMap { $0.lines.map(\.audioName) }
        names += pack.wordGames.flatMap { [$0.promptLine.audioName, $0.revealLine.audioName] }
        names += pack.questions.map { $0.answerLine.audioName }
        names += pack.phrases.values.flatMap { $0.map(\.audioName) }

        let duplicates = Dictionary(grouping: names, by: { $0 }).filter { $0.value.count > 1 }.keys
        XCTAssertTrue(duplicates.isEmpty, "these recordings would overwrite each other: \(Array(duplicates))")
    }

    func testEveryPhraseGroupTheCodeAsksForExists() throws {
        let pack = try ContentPack.shipped()
        for group in PhraseGroup.allCases {
            XCTAssertNotNil(pack.phrase(group), "phrases.json has no \(group.rawValue) group")
        }
    }

    func testBothPrayersAndRhymesArePresent() throws {
        let pack = try ContentPack.shipped()
        XCTAssertFalse(pack.sets(of: .prayer).isEmpty)
        XCTAssertFalse(pack.sets(of: .rhyme).isEmpty)
    }

    func testPlaceholderPrayersAreMarkedAsSuch() throws {
        // The family supplies the real texts. Anything standing in must say so, or it
        // will quietly ship.
        let pack = try ContentPack.shipped()
        for set in pack.sets(of: .prayer) {
            XCTAssertTrue(set.isPlaceholder, "prayer set \(set.id) is not marked placeholder")
        }
    }

    func testEveryWordGameCanBePlayedWithoutRecognition() throws {
        // The fallback shows pictures and the child taps one. A game without them is
        // unplayable on a device where on-device recognition is unavailable — which the
        // brief says must never happen.
        //
        // `choices` are picture names, not spoken answers: tapping the cow answers
        // "what sound does a cow make", so they deliberately do not have to appear in
        // `accepted`.
        let pack = try ContentPack.shipped()
        for game in pack.wordGames {
            XCTAssertGreaterThanOrEqual(game.choices.count, 2,
                                        "word game \(game.id) has no tap-to-choose fallback")
            XCTAssertEqual(Set(game.choices).count, game.choices.count,
                           "word game \(game.id) offers the same picture twice")
        }
    }

    func testEveryWordGameAcceptsSomething() throws {
        let pack = try ContentPack.shipped()
        for game in pack.wordGames {
            XCTAssertFalse(game.accepted.isEmpty, "word game \(game.id) accepts no answer at all")
            XCTAssertTrue(AnswerMatcher.accepts(heard: game.accepted[0], anyOf: game.accepted),
                          "word game \(game.id): its own first accepted answer does not match")
            XCTAssertFalse(game.reveal.isEmpty,
                           "word game \(game.id) has nothing to say when the answer is not on the list")
        }
    }
}
