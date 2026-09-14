import XCTest
@testable import LittleOwl

/// `OwlAnswerGuard` is the only thing between a generated sentence and a five-year-old's
/// ears, so it is the piece of the brain that gets tested. The networking around it is
/// a POST and a JSON field; what matters is what it is allowed to hand over.
///
/// The test for every rejection is the same, and it is the point of the whole design:
/// **rejecting costs nothing.** A nil here is the owl saying "I do not know that one",
/// which is what this mode did before any of this existed. So the guard can afford to
/// be strict, and these tests hold it to being strict.
final class OwlBrainTests: XCTestCase {

    // MARK: What gets through

    func testAPlainAnswerGetsThrough() {
        let answer = OwlAnswerGuard.clean("The sky looks blue because sunlight bounces around in the air. Blue bounces the most!")
        XCTAssertEqual(answer, "The sky looks blue because sunlight bounces around in the air. Blue bounces the most!")
    }

    func testNewlinesBecomeSpaces() {
        // The synthesiser reads a newline as a pause, and a pause in the wrong place
        // sounds like the owl faltering.
        let answer = OwlAnswerGuard.clean("Cats purr when\n they are happy.\n\n  It is their way of smiling.")
        XCTAssertEqual(answer, "Cats purr when they are happy. It is their way of smiling.")
    }

    func testOnlyTheFirstTwoSentencesAreKept() {
        let answer = OwlAnswerGuard.clean(
            "Rain comes from clouds. Clouds are made of tiny drops of water. "
            + "When the drops get heavy they fall. That is rain!")
        XCTAssertEqual(answer, "Rain comes from clouds. Clouds are made of tiny drops of water.")
    }

    func testAnExclamationOrAQuestionEndsASentenceToo() {
        XCTAssertEqual(
            OwlAnswerGuard.clean("Camels keep fat in their humps! Not water, which is what most people think."),
            "Camels keep fat in their humps! Not water, which is what most people think.")
    }

    func testNumbersAndDashesAreOrdinarySpeech() {
        // An early cut rejected both, which would have had the owl shrugging at
        // perfectly good answers.
        XCTAssertEqual(OwlAnswerGuard.clean("A spider has 8 legs - two more than an insect."),
                       "A spider has 8 legs - two more than an insect.")
        // Not "It takes about one. Five seconds for light to reach the moon."
        XCTAssertEqual(OwlAnswerGuard.clean("It takes about 1.5 seconds for light to reach the moon."),
                       "It takes about 1.5 seconds for light to reach the moon.")
    }

    // MARK: What does not

    func testAnUnfinishedSentenceIsNotSpoken() {
        // What a model truncated by the token limit produces.
        XCTAssertNil(OwlAnswerGuard.clean("The moon goes around the Earth and that is why it looks like it"))
    }

    func testNothingIsNotAnAnswer() {
        XCTAssertNil(OwlAnswerGuard.clean(""))
        XCTAssertNil(OwlAnswerGuard.clean("   \n  "))
        XCTAssertNil(OwlAnswerGuard.clean("Yes."))
    }

    func testTheOwlIsNeverAModel() {
        for meta in [
            "As an AI, I should say that the sky is blue.",
            "I am an AI assistant and I cannot be sure.",
            "My guidelines say I should not answer that.",
            "As a language model I do not have feelings."
        ] {
            XCTAssertNil(OwlAnswerGuard.clean(meta), "the owl said: \(meta)")
        }
    }

    func testNothingWrittenToBeReadIsSpoken() {
        for formatted in [
            "Here are the reasons: * water * air * light.",
            "You can read more at https://example.com/sky today.",
            "```\nprint(\"blue\")\n```",
            "- Clouds hold water. - Water falls as rain.",
            "The **most** important part is the water.",
            "1. Clouds gather. 2. Rain falls."
        ] {
            XCTAssertNil(OwlAnswerGuard.clean(formatted), "the owl read out: \(formatted)")
        }
    }

    func testEmojiAreNotSpoken() {
        XCTAssertNil(OwlAnswerGuard.clean("The sky is blue 🌈 because of the light!"))
    }

    func testALongAnswerIsNotAnAnswerForAFiveYearOld() {
        let long = String(repeating: "The sky is blue because of the way light scatters. ",
                          count: 10)
        // Two sentences of that is still under the cap, so the cap is tested directly.
        XCTAssertGreaterThan(long.count, OwlAnswerGuard.maxCharacters)
        let single = String(repeating: "word ", count: 80) + "."
        XCTAssertNil(OwlAnswerGuard.clean(single))
    }

    // MARK: Declining

    func testDecliningIsHandedBackToTheMode() {
        // The mode has its own written line for this, which may be recorded in the owl's
        // own voice. Reading the prompt's wording aloud in a synthesised one would be a
        // worse version of the same sentence.
        XCTAssertNil(OwlAnswerGuard.clean(OwlPrompt.declined))
        XCTAssertNil(OwlAnswerGuard.clean("I don't know that one. Ask your grown-up!"))
        XCTAssertNil(OwlAnswerGuard.clean("I cannot answer that, but your grown-up can."))
    }

    func testThePromptSaysWhatTheGuardListensFor() {
        // These two drifting apart is silent: the model would decline in wording the
        // guard does not recognise, and a child would hear it read out.
        XCTAssertTrue(OwlPrompt.system.contains(OwlPrompt.declined),
                      "the prompt no longer asks for the sentence the guard watches for")
    }

    // MARK: Reading the reply

    // Two services, two document shapes, and the parsing is where this breaks quietly:
    // a socket either opens or times out, but a reply whose shape changed just returns
    // nil forever. So both live outside the networking and are tested in every build,
    // including the ones compiled with no networking at all.

    func testAnAnthropicReply() {
        let json = """
            {"id":"msg_1","type":"message","role":"assistant",
             "content":[{"type":"text","text":"Because the light bounces about."}]}
            """
        XCTAssertEqual(BrainReply.fromAnthropic(Data(json.utf8)),
                       "Because the light bounces about.")
    }

    func testAnthropicSkipsBlocksThatAreNotText() {
        let json = """
            {"content":[{"type":"thinking","thinking":"hmm"},
                        {"type":"text","text":"Because it bounces."}]}
            """
        XCTAssertEqual(BrainReply.fromAnthropic(Data(json.utf8)), "Because it bounces.")
    }

    func testADeepSeekReply() {
        let json = """
            {"id":"x","object":"chat.completion","model":"deepseek-v4-pro",
             "choices":[{"index":0,"message":{"role":"assistant",
                         "content":"Because the light bounces about."},
                         "finish_reason":"stop"}]}
            """
        XCTAssertEqual(BrainReply.fromDeepSeek(Data(json.utf8)),
                       "Because the light bounces about.")
    }

    func testDeepSeekReasoningIsNotReadToTheChild() {
        // A reasoning model puts its working in reasoning_content. The owl says the
        // answer; it does not think out loud at a five-year-old.
        let json = """
            {"choices":[{"message":{"role":"assistant",
                         "reasoning_content":"The user is five. I should be simple.",
                         "content":"Because the light bounces about."}}]}
            """
        XCTAssertEqual(BrainReply.fromDeepSeek(Data(json.utf8)),
                       "Because the light bounces about.")
    }

    func testAnErrorBodyIsNotAnAnswer() {
        // What either service sends on a bad key. Nothing here may reach a child.
        let anthropic = #"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#
        let deepseek = #"{"error":{"message":"Authentication Fails","type":"authentication_error"}}"#

        XCTAssertNil(BrainReply.fromAnthropic(Data(anthropic.utf8)))
        XCTAssertNil(BrainReply.fromDeepSeek(Data(deepseek.utf8)))
        // And neither parser accepts the other's document.
        XCTAssertNil(BrainReply.fromAnthropic(Data(#"{"choices":[{"message":{"content":"hi there friend"}}]}"#.utf8)))
        XCTAssertNil(BrainReply.fromDeepSeek(Data(#"{"content":[{"type":"text","text":"hi there friend"}]}"#.utf8)))
    }

    func testRubbishIsNotAnAnswer() {
        for junk in ["", "not json at all", "[]", "{}", "null"] {
            XCTAssertNil(BrainReply.fromAnthropic(Data(junk.utf8)), junk)
            XCTAssertNil(BrainReply.fromDeepSeek(Data(junk.utf8)), junk)
        }
    }

    func testEveryProviderIsRoutedSomewhere() {
        // A provider added without a branch in `text(_:from:)` would silently never
        // answer, which looks exactly like a network problem.
        let bodies: [BrainProvider: String] = [
            .anthropic: #"{"content":[{"type":"text","text":"Because it bounces."}]}"#,
            .deepseek: #"{"choices":[{"message":{"content":"Because it bounces."}}]}"#
        ]
        for provider in BrainProvider.allCases {
            guard let body = bodies[provider] else {
                XCTFail("no fixture for \(provider.name)")
                continue
            }
            XCTAssertEqual(BrainReply.text(Data(body.utf8), from: provider),
                           "Because it bounces.", provider.name)
        }
    }

    // MARK: Which service

    func testEveryProviderSaysWhereTheQuestionGoes() {
        // A parent choosing this for their own child is entitled to know it from the
        // screen rather than from the source.
        for provider in BrainProvider.allCases {
            XCTAssertFalse(provider.name.isEmpty)
            XCTAssertFalse(provider.destination.isEmpty, "\(provider.name) does not say where it sends the question")
            XCTAssertTrue(provider.keyPrompt.lowercased().contains("key"))
        }
    }

    // MARK: The prompt itself

    func testThePromptSaysWhoItIsTalkingTo() {
        let prompt = OwlPrompt.system.lowercased()
        // The whole feature is this sentence. A rewrite that loses it is a rewrite that
        // changes what a child hears.
        XCTAssertTrue(prompt.contains("five-year-old"))
        XCTAssertTrue(prompt.contains("owl"))
    }

    func testThePromptForbidsTheThingsTheGuardCannotCatch() {
        let prompt = OwlPrompt.system.lowercased()
        // The guard checks shape, not subject. Everything about subject matter lives
        // here, so if this stops being true nothing downstream notices.
        for subject in ["death", "violence", "sex"] {
            XCTAssertTrue(prompt.contains(subject), "the prompt stopped ruling out \(subject)")
        }
        XCTAssertTrue(prompt.contains("never ask the child for their name"))
    }
}
