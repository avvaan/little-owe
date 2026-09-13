import XCTest
@testable import LittleOwl

/// The matcher decides whether a three-year-old's mumble counted. Too strict and the
/// owl shrugs at a correct answer; too loose and it congratulates silence.
final class SpeechMatchingTests: XCTestCase {

    // MARK: Tokens

    func testTokensDropFunctionWordsAndPunctuation() {
        XCTAssertEqual(SpeechMatching.tokens("Why is the sky blue?"), ["sky", "blue"])
        XCTAssertEqual(SpeechMatching.tokens("WHERE DOES RAIN COME FROM"), ["rain", "come"])
    }

    func testTokensKeepContentVerbs() {
        // "come" must survive: dropping it would gut "where does rain come from".
        XCTAssertTrue(SpeechMatching.tokens("does it come").contains("come"))
        XCTAssertTrue(SpeechMatching.tokens("why do leaves fall").contains("fall"))
    }

    func testSingularHandlesTheCommonPlurals() {
        XCTAssertEqual(SpeechMatching.singular("cats"), "cat")
        XCTAssertEqual(SpeechMatching.singular("boxes"), "box")
        XCTAssertEqual(SpeechMatching.singular("puppies"), "puppy")
    }

    func testIrregularPluralsAreNotStemmed() {
        // "leaves" becomes "leave", not "leaf". Nothing here tries to be a real
        // stemmer, because guessing wrong mangles a word the child actually said.
        // Two-of-three keyword matching is what absorbs this; a question resting on a
        // single irregular plural would need an alternate phrasing instead.
        XCTAssertEqual(SpeechMatching.singular("leaves"), "leave")
        XCTAssertEqual(SpeechMatching.singular("mice"), "mice")
    }

    func testSingularLeavesShortAndDoubleSWordsAlone() {
        XCTAssertEqual(SpeechMatching.singular("is"), "is")
        XCTAssertEqual(SpeechMatching.singular("grass"), "grass")
        XCTAssertEqual(SpeechMatching.singular("bus"), "bus")
    }

    // MARK: Word game answers

    func testAcceptsAnAnswerWithExtraWordsAround() {
        XCTAssertTrue(AnswerMatcher.accepts(heard: "um, a monkey I think", anyOf: ["monkey", "mouse"]))
        XCTAssertTrue(AnswerMatcher.accepts(heard: "moo moo moo", anyOf: ["moo"]))
    }

    func testAcceptsIgnoresArticles() {
        XCTAssertTrue(AnswerMatcher.accepts(heard: "the chair", anyOf: ["chair"]))
        XCTAssertTrue(AnswerMatcher.accepts(heard: "chair", anyOf: ["the chair"]))
    }

    func testRejectsSomethingElseEntirely() {
        XCTAssertFalse(AnswerMatcher.accepts(heard: "a banana", anyOf: ["chair"]))
        XCTAssertFalse(AnswerMatcher.accepts(heard: "", anyOf: ["chair"]))
        XCTAssertFalse(AnswerMatcher.accepts(heard: "the the the", anyOf: ["chair"]))
    }

    func testPrefersTheLongerAcceptedAnswer() {
        XCTAssertEqual(
            AnswerMatcher.matched(heard: "a red apple", anyOf: ["apple", "red apple"]),
            "red apple"
        )
    }

    // MARK: Why questions

    private func matcher(_ questions: [(String, [String], [String])]) -> QuestionMatcher {
        QuestionMatcher(questions.map { id, keywords, alternates in
            Question.fixture(id: id, keywords: keywords, alternates: alternates)
        })
    }

    func testMatchesTheObviousPhrasing() {
        let m = matcher([("sky-blue", ["sky", "blue"], []), ("grass-green", ["grass", "green"], [])])
        XCTAssertEqual(m.question(for: "why is the sky blue")?.id, "sky-blue")
        XCTAssertEqual(m.question(for: "why the grass green")?.id, "grass-green")
    }

    func testMatchesAnAuthoredAlternate() {
        let m = matcher([("rain", ["rain", "come"], ["why does it rain"])])
        XCTAssertEqual(m.question(for: "why does it rain")?.id, "rain")
    }

    func testTwoOfThreeKeywordsIsEnoughButOneOfTwoIsNot() {
        // "leaves" stems to "leave", so the leaf keyword misses — and the question
        // still matches on the other two. That slack is the point of the threshold.
        let three = matcher([("leaves", ["leaf", "fall", "tree"], [])])
        XCTAssertEqual(three.question(for: "why do leaves fall off trees")?.id, "leaves")

        let two = matcher([("sky-blue", ["sky", "blue"], [])])
        XCTAssertNil(two.question(for: "what is the sky"))
    }

    func testTheMoreSpecificQuestionWinsATie() {
        // Both score a perfect 1.0. The one that asked for two words and got both is
        // the more specific fit and should win.
        let m = matcher([("night", ["night"], []), ("owls-night", ["owl", "night"], [])])
        XCTAssertEqual(m.question(for: "why are owls awake at night")?.id, "owls-night")
    }

    func testAQuestionWithNoMatchingKeywordsIsNotConsideredAtAll() {
        let m = matcher([("sleep", ["sleep"], []), ("owls-night", ["owl", "night"], [])])
        XCTAssertEqual(m.question(for: "why are owls awake at night")?.id, "owls-night")
    }

    func testNoMatchRatherThanAWrongOne() {
        let m = matcher([("sky-blue", ["sky", "blue"], []), ("rain", ["rain", "come"], [])])
        XCTAssertNil(m.question(for: "what is your favourite colour"))
        XCTAssertNil(m.question(for: "why"))
        XCTAssertNil(m.question(for: ""))
    }

    func testEveryShippedQuestionMatchesItsOwnCanonicalPhrasing() throws {
        let pack = try ContentPack.shipped()
        let matcher = QuestionMatcher(pack.questions)

        for question in pack.questions {
            let matched = matcher.question(for: question.text)
            XCTAssertNotNil(matched, "\(question.id) does not match its own text: \(question.text)")
            XCTAssertEqual(matched?.id, question.id,
                           "\(question.id) is shadowed by \(matched?.id ?? "nothing") for its own phrasing")
        }
    }
}
