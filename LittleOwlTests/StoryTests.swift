import XCTest
import SpriteKit
@testable import LittleOwl

/// Stories has three things worth testing without a running scene: the word ranges that
/// drive the captions, the caption layout itself, and whether the shipped stories are
/// actually the length the brief asks for.
final class StoryTests: XCTestCase {

    // MARK: Word ranges

    func testWordRangesCoverTheWordsInOrder() {
        let text = "Twinkle, twinkle, little star."
        let ranges = OwlVoice.wordRanges(in: text)
        let ns = text as NSString
        XCTAssertEqual(ranges.map { ns.substring(with: $0) },
                       ["Twinkle", "twinkle", "little", "star"])
    }

    func testWordRangesHandleAnEmptyLine() {
        XCTAssertTrue(OwlVoice.wordRanges(in: "").isEmpty)
        XCTAssertTrue(OwlVoice.wordRanges(in: "   ").isEmpty)
    }

    // MARK: Captions

    func testCaptionKeepsPunctuationWithItsWord() {
        let caption = CaptionNode(maxWidth: 900)
        caption.show("Hello, little star.")
        // Three display words: a reader sees "Hello," as one thing, not two.
        XCTAssertEqual(caption.wordTexts, ["Hello,", "little", "star."])
    }

    func testCaptionWrapsOntoMoreThanOneLine() {
        let narrow = CaptionNode(maxWidth: 200, fontSize: 40)
        narrow.show("The quick brown fox jumped over the lazy dog and kept going")

        let ys = Set(narrow.children.compactMap { ($0 as? SKLabelNode)?.position.y })
        XCTAssertGreaterThan(ys.count, 1, "everything landed on one line despite the narrow width")
        XCTAssertGreaterThan(narrow.height, 0)
    }

    func testCaptionStaysInsideItsWidth() {
        let caption = CaptionNode(maxWidth: 600, fontSize: 40)
        caption.show("A story about a fox who found a small red mitten in the snow one morning")

        for label in caption.children.compactMap({ $0 as? SKLabelNode }) {
            XCTAssertLessThanOrEqual(label.position.x + label.frame.width, 320,
                                     "'\(label.text ?? "")' runs past half the caption width")
            XCTAssertGreaterThanOrEqual(label.position.x, -320)
        }
    }

    func testHighlightingLightsOneWordAtATime() {
        let text = "Twinkle, twinkle, little star."
        let caption = CaptionNode(maxWidth: 900)
        caption.show(text)

        let ranges = OwlVoice.wordRanges(in: text)

        caption.highlight(range: ranges[2])          // "little"
        XCTAssertEqual(caption.highlightedIndex, 2)
        XCTAssertEqual(caption.wordTexts[2], "little")

        caption.highlight(range: ranges[3])          // "star"
        XCTAssertEqual(caption.highlightedIndex, 3)
        XCTAssertEqual(caption.wordTexts[3], "star.")
    }

    func testAnUnmatchedRangeLeavesTheLastWordLit() {
        // Punctuation and gaps between words must not blank the caption mid-sentence.
        let caption = CaptionNode(maxWidth: 900)
        caption.show("Hello there.")
        caption.highlight(range: NSRange(location: 0, length: 5))
        XCTAssertEqual(caption.highlightedIndex, 0)

        caption.highlight(range: NSRange(location: 500, length: 2))
        XCTAssertEqual(caption.highlightedIndex, 0, "an unmatched range blanked the caption")
    }

    func testClearingEmptiesTheCaption() {
        let caption = CaptionNode(maxWidth: 900)
        caption.show("Something to say")
        XCTAssertFalse(caption.children.isEmpty)
        caption.clear()
        XCTAssertTrue(caption.children.isEmpty)
        XCTAssertEqual(caption.height, 0)
    }

    // MARK: Hero cards

    func testEveryShippedHeroHasADrawableSilhouette() throws {
        let pack = try ContentPack.shipped()
        for hero in pack.heroes {
            let path = HeroSilhouette.path(for: hero.id, height: 200)
            let box = path.boundingBox
            XCTAssertGreaterThan(box.width, 40, "\(hero.id) draws almost nothing")
            XCTAssertGreaterThan(box.height, 40, "\(hero.id) draws almost nothing")
        }
    }

    func testAnUnknownHeroStillDrawsSomething() {
        // A pack can name a hero this build has never heard of; a blank card would look
        // broken, so the fallback has to be a real shape.
        let box = HeroSilhouette.path(for: "platypus", height: 200).boundingBox
        XCTAssertGreaterThan(box.width, 40)
    }

    func testTheCardRowFitsTheRoom() throws {
        let pack = try ContentPack.shipped()
        let cards = CGFloat(pack.heroes.count)
        let width = cards * HeroPicker.cardSize.width + (cards - 1) * 28
        XCTAssertLessThan(width, RoomLayout.designSize.width - 80,
                          "\(Int(cards)) hero cards do not fit across the room")
    }

    // MARK: The shipped stories

    /// A slow bedtime reading for a three- to six-year-old runs about 130 words a minute.
    private let wordsPerMinute = 130.0

    func testEveryStoryRunsForAsLongAsTheBriefAsks() throws {
        let pack = try ContentPack.shipped()
        for story in pack.stories {
            let words = story.pages.reduce(0) { $0 + $1.text.split(separator: " ").count }
            let seconds = Double(words) / wordsPerMinute * 60
            XCTAssertGreaterThanOrEqual(seconds, 60,
                                        "\(story.id) reads in about \(Int(seconds))s; the brief asks for 60 to 120")
            XCTAssertLessThanOrEqual(seconds, 120,
                                     "\(story.id) reads for about \(Int(seconds))s; the brief asks for 60 to 120")
        }
    }

    func testEveryPageHasSomethingToSay() throws {
        let pack = try ContentPack.shipped()
        for story in pack.stories {
            XCTAssertGreaterThanOrEqual(story.pages.count, 4,
                                        "\(story.id) has too few pages to feel like a book")
            for page in story.pages {
                XCTAssertFalse(page.text.trimmingCharacters(in: .whitespaces).isEmpty,
                               "\(story.id)/\(page.id) has no text")
                XCTAssertNotNil(page.illustration,
                                "\(story.id)/\(page.id) names no illustration, so the artist has nothing to fill")
            }
        }
    }

    func testEveryPageFitsTheCaptionArea() throws {
        // A page whose caption needs more than four lines has outgrown the space under
        // the picture, and would push off the bottom of the screen.
        let pack = try ContentPack.shipped()
        let caption = CaptionNode(maxWidth: 900, fontSize: 40)

        for story in pack.stories {
            for page in story.pages {
                caption.show(page.text)
                XCTAssertLessThanOrEqual(caption.height, 40 * 1.34 * 4,
                                         "\(story.id)/\(page.id) needs more than four caption lines")
            }
        }
    }
}
