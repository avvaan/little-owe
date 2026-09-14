import XCTest
import SpriteKit
@testable import LittleOwl

/// Word games and "Why?". The two modes that answer a child out loud, and the content
/// bank they answer from.
///
/// The promise worth testing here is not that the matcher is clever. It is that the owl
/// never answers a question nobody asked, and never has a "wrong" branch to take.
final class WordGameAndWhyTests: XCTestCase {

    // MARK: The question bank

    func testTheBankIsTheSizeTheBriefAsksFor() throws {
        let pack = try ContentPack.shipped()
        XCTAssertGreaterThanOrEqual(pack.questions.count, 100)
        XCTAssertLessThanOrEqual(pack.questions.count, 200)
    }

    func testEveryAuthoredAlternateResolvesToItsOwnQuestion() throws {
        // The canonical phrasing is already covered. Alternates are where a new entry
        // quietly steals an old one's answers, because they are written months apart and
        // nobody re-reads the other hundred.
        let pack = try ContentPack.shipped()
        let matcher = QuestionMatcher(pack.questions)

        for question in pack.questions {
            for phrasing in question.alternates {
                let matched = matcher.question(for: phrasing)
                XCTAssertNotNil(matched, "\(question.id) has an alternate nothing matches: \(phrasing)")
                XCTAssertEqual(matched?.id, question.id,
                               "\(question.id)'s alternate '\(phrasing)' is answered by \(matched?.id ?? "nothing")")
            }
        }
    }

    func testEveryQuestionHasAnAnswerWorthSaying() throws {
        let pack = try ContentPack.shipped()
        for question in pack.questions {
            let sentences = question.answer.split(whereSeparator: { ".!?".contains($0) })
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            XCTAssertGreaterThanOrEqual(sentences.count, 2,
                                        "\(question.id)'s answer is one sentence: \(question.answer)")
            XCTAssertLessThanOrEqual(sentences.count, 4,
                                     "\(question.id)'s answer runs long for a four-year-old")
            XCTAssertFalse(question.keywords.isEmpty, "\(question.id) has no keywords")
        }
    }

    func testAQuestionOutsideTheBankGetsNoAnswerAtAll() throws {
        // The owl must never invent one. A miss has to stay a miss.
        let pack = try ContentPack.shipped()
        let matcher = QuestionMatcher(pack.questions)

        for asked in ["can i have a biscuit",
                      "where is my mummy",
                      "what is my teacher called",
                      "is it my birthday tomorrow"] {
            XCTAssertNil(matcher.question(for: asked),
                         "'\(asked)' was answered by \(matcher.question(for: asked)?.id ?? "")")
        }
    }

    func testCommonPhrasingsNobodyAuthoredStillLand() throws {
        let pack = try ContentPack.shipped()
        let matcher = QuestionMatcher(pack.questions)

        let trials = [
            ("why is the sky blue", "sky-blue"),
            ("where does the rain come from", "rain-from"),
            ("why does my cat purr", "cats-purr"),
            ("why do dogs bark so much", "dogs-bark"),
            ("how does a fridge stay cold", "fridge-cold"),
            ("why do things fall down to the ground", "things-fall"),
        ]
        for (asked, expected) in trials {
            XCTAssertEqual(matcher.question(for: asked)?.id, expected, "'\(asked)'")
        }
    }

    func testASingleContentWordDoesNotBecomeAWildcard() throws {
        // An entry whose keywords or alternates reduce to one content word matches on
        // that word wherever it appears. That is right for "volcano" and wrong for
        // "colour" — "what is my favourite colour" is not a question about how eyes work.
        let pack = try ContentPack.shipped()
        let matcher = QuestionMatcher(pack.questions)

        XCTAssertNil(matcher.question(for: "what is my favourite colour"))
        XCTAssertNil(matcher.question(for: "why do we wave"))
        XCTAssertEqual(matcher.question(for: "what is a volcano")?.id, "volcano")
    }

    // MARK: Word games

    func testEveryGameHasChoicesForADeviceThatCannotHear() throws {
        let pack = try ContentPack.shipped()
        for game in pack.wordGames {
            XCTAssertGreaterThanOrEqual(game.choices.count, 3,
                                        "\(game.id) has too few cards for the no-recognition path")
            XCTAssertLessThanOrEqual(game.choices.count, 3,
                                     "\(game.id) has more cards than a row fits")
            XCTAssertEqual(Set(game.choices).count, game.choices.count,
                           "\(game.id) offers the same card twice")
        }
    }

    func testTheFirstChoiceIsAlwaysAnAcceptedAnswer() throws {
        // The mode shuffles the row and remembers where the first one went, so the
        // content file's convention is load-bearing.
        let pack = try ContentPack.shipped()
        for game in pack.wordGames {
            guard let first = game.choices.first else { continue }
            XCTAssertTrue(AnswerMatcher.accepts(heard: first, anyOf: game.accepted),
                          "\(game.id)'s first card '\(first)' is not one of its accepted answers")
        }
    }

    func testTheOtherChoicesAreNotAlsoCorrect() throws {
        let pack = try ContentPack.shipped()
        for game in pack.wordGames {
            for wrong in game.choices.dropFirst() {
                XCTAssertFalse(AnswerMatcher.accepts(heard: wrong, anyOf: game.accepted),
                               "\(game.id) offers '\(wrong)' as a wrong card, but it is accepted")
            }
        }
    }

    func testEveryGameHasSomethingKindToSayWhenTheAnswerIsNotOnTheList() throws {
        let pack = try ContentPack.shipped()
        for game in pack.wordGames {
            XCTAssertFalse(game.reveal.trimmingCharacters(in: .whitespaces).isEmpty,
                           "\(game.id) has nothing to say when the child misses")
            XCTAssertFalse(game.accepted.isEmpty, "\(game.id) accepts nothing at all")
        }
    }

    func testTheOwlHasStockLinesForBothNewModes() throws {
        let pack = try ContentPack.shipped()
        for group in [PhraseGroup.askInvite, .chooseInvite, .unknownQuestion, .kindTry, .praise] {
            XCTAssertFalse(pack.phrases[group]?.isEmpty ?? true,
                           "the pack has no \(group.rawValue) lines")
        }
    }

    // MARK: The cards a child taps

    func testAChoiceRowFitsTheRoom() {
        XCTAssertLessThanOrEqual(ChoiceRow.rowWidth(3), RoomLayout.designSize.width - 80)
        XCTAssertGreaterThanOrEqual(ChoiceRow.cardSize.width, RoomLayout.minimumTapTarget)
        XCTAssertGreaterThanOrEqual(ChoiceRow.cardSize.height, RoomLayout.minimumTapTarget)
    }

    func testEveryChoiceCardIsReachableWhereItSits() {
        let options = ["monkey", "rabbit", "tiger"].map { word in
            SpokenChoices.Option(line: SpokenText(id: word, text: word, stem: "choice_\(word)"))
        }
        let row = ChoiceRow(options: options, language: "en")

        for (index, card) in row.cards.enumerated() {
            XCTAssertEqual(row.index(at: card.position), index, "card \(index) is not reachable")
        }
        XCTAssertNil(row.index(at: CGPoint(x: 5000, y: 0)))
    }

}
