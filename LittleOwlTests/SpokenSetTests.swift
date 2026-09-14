import XCTest
import SpriteKit
@testable import LittleOwl

/// Prayers and rhymes. Most of what matters here is a promise about behaviour rather
/// than a calculation: that the owl never grades a child, that it works on a device that
/// cannot hear, and that a parent's choice of sets is honoured exactly.
final class SpokenSetTests: XCTestCase {

    // MARK: What counts as having said it

    func testAFragmentOfAShortLineCounts() {
        // "Twinkle, twinkle, little star," is four words, so one is enough. A
        // three-year-old repeating a rhyme gets a fragment of it out, and that is the
        // whole bar.
        XCTAssertEqual(RepeatJudge.judge(line: "Twinkle, twinkle, little star,", heard: "twinkle"),
                       .repeated)
    }

    func testALongLineNeverAsksForMoreThanTheCap() {
        let long = "All the king's horses and all the king's men and everyone else besides"
        XCTAssertEqual(RepeatJudge.requiredWords(forLineOf: RepeatJudge.wordCount(of: long)),
                       RepeatJudge.cap)
        XCTAssertEqual(RepeatJudge.judge(line: long, heard: "all the king's horses"), .repeated)
    }

    func testSilenceIsNotEnough() {
        XCTAssertEqual(RepeatJudge.judge(line: "Gently down the stream.", heard: nil), .notEnough)
        XCTAssertEqual(RepeatJudge.judge(line: "Gently down the stream.", heard: ""), .notEnough)
    }

    func testOneStrayWordAgainstALongLineIsNotEnough() {
        // A cough, a sibling, the television. The owl says the line again rather than
        // praising a door closing.
        let long = "Watch over me all through the night, and wake me with the morning light."
        XCTAssertEqual(RepeatJudge.judge(line: long, heard: "the"), .notEnough)
    }

    func testItNeverChecksWhichWords() {
        // The point of the whole type: length only. Nothing here resembles the line and
        // the owl is still delighted.
        XCTAssertEqual(RepeatJudge.judge(line: "Now I lay me down to sleep,",
                                         heard: "banana banana banana"), .repeated)
    }

    func testEveryLineAsksForAtLeastOneWord() {
        for words in 0...40 {
            XCTAssertGreaterThanOrEqual(RepeatJudge.requiredWords(forLineOf: words), 1)
            XCTAssertLessThanOrEqual(RepeatJudge.requiredWords(forLineOf: words), RepeatJudge.cap)
        }
    }

    // MARK: The pause on a device that cannot hear

    func testTheFallbackPauseGrowsWithTheLineAndStaysInHumanBounds() {
        var previous: TimeInterval = 0
        for words in 1...30 {
            let pause = RepeatJudge.fallbackPause(forLineOf: words)
            XCTAssertGreaterThanOrEqual(pause, 2.5)
            XCTAssertLessThanOrEqual(pause, 9.0)
            XCTAssertGreaterThanOrEqual(pause, previous, "the pause shrank at \(words) words")
            previous = pause
        }
    }

    func testEveryShippedLineGetsAPauseAChildCanUse() throws {
        let pack = try ContentPack.shipped()
        for set in pack.spokenSets {
            for line in set.lines {
                let pause = RepeatJudge.fallbackPause(forLineOf: RepeatJudge.wordCount(of: line.text))
                XCTAssertGreaterThan(pause, 2.0, "\(set.id)/\(line.id) gives no time to answer")
            }
        }
    }

    // MARK: What a parent left on the lamp

    private func settings() -> ParentSettings {
        let suite = UserDefaults(suiteName: "SpokenSetTests-\(UUID().uuidString)")!
        return ParentSettings(defaults: suite)
    }

    func testNoChoiceMeansEverySet() throws {
        let pack = try ContentPack.shipped()
        let settings = settings()
        XCTAssertNil(settings.enabledSpokenSetIDs)
        XCTAssertEqual(settings.spokenSets(from: pack).map(\.id), pack.spokenSets.map(\.id))
    }

    func testAChoiceIsHonouredInPackOrder() throws {
        let pack = try ContentPack.shipped()
        let settings = settings()
        // Deliberately out of order, and with an id the pack does not have.
        settings.enabledSpokenSetIDs = ["rhyme-row", "prayer-morning", "no-such-set"]

        XCTAssertEqual(settings.spokenSets(from: pack).map(\.id), ["prayer-morning", "rhyme-row"],
                       "cards must keep pack order so a child finds the same one twice")
    }

    func testAParentCanTurnEverythingOff() throws {
        let pack = try ContentPack.shipped()
        let settings = settings()
        settings.enabledSpokenSetIDs = []
        XCTAssertTrue(settings.spokenSets(from: pack).isEmpty)
    }

    // MARK: The cards

    func testRowsAreBalancedAndNeverTooWide() {
        XCTAssertEqual(SpokenSetPicker.rows(for: 0), [])
        XCTAssertEqual(SpokenSetPicker.rows(for: 1), [1])
        // The whole shipped pack fits one row, which is the only way it stays clear of
        // the owl.
        XCTAssertEqual(SpokenSetPicker.rows(for: 7), [7])
        // Past that it wraps, as evenly as it can: eight is four and four, not seven
        // and one.
        XCTAssertEqual(SpokenSetPicker.rows(for: 8), [4, 4])
        XCTAssertEqual(SpokenSetPicker.rows(for: 14), [7, 7])

        for count in 1...16 {
            let rows = SpokenSetPicker.rows(for: count)
            XCTAssertEqual(rows.reduce(0, +), count)
            XCTAssertLessThanOrEqual(rows.max() ?? 0, SpokenSetPicker.maxPerRow)
            XCTAssertLessThanOrEqual(SpokenSetPicker.rowWidth(rows.max() ?? 0),
                                     RoomLayout.designSize.width - 80,
                                     "a row of \(rows.max() ?? 0) cards runs off the room")
        }
    }

    func testCardsAreComfortablyBiggerThanTheTapTargetFloor() {
        XCTAssertGreaterThanOrEqual(SpokenSetPicker.cardSize.width, RoomLayout.minimumTapTarget)
        XCTAssertGreaterThanOrEqual(SpokenSetPicker.cardSize.height, RoomLayout.minimumTapTarget)
    }

    func testTheCardsStayClearOfTheOwl() throws {
        // The owl stays on its perch while the cards are up, so the cards have to go
        // where it is not. A card on the owl's chest is a card a child taps by accident
        // while reaching for the owl to leave.
        let pack = try ContentPack.shipped()
        let picker = SpokenSetPicker(sets: pack.spokenSets)

        XCTAssertEqual(SpokenSetPicker.rows(for: pack.spokenSets.count).count, 1,
                       "the shipped pack no longer fits one row")
        XCTAssertLessThan(picker.contentHeight, RoomLayout.owlHome.y - 60,
                          "the cards cannot fit below the owl's feet")
    }

    func testEveryCardIsReachableWhereItSits() throws {
        // The hit area is in the card's own space and the cards are spread across the
        // row, so a picker that forgets to subtract the card's position offers exactly
        // one reachable card out of seven.
        let pack = try ContentPack.shipped()
        let picker = SpokenSetPicker(sets: pack.spokenSets)

        for card in picker.cards {
            var picked: SpokenSet?
            picker.onPick = { picked = $0 }
            XCTAssertTrue(picker.handleTap(at: card.position), "\(card.set.id) is not reachable")
            XCTAssertEqual(picked?.id, card.set.id)
        }
    }

    func testCardsStayReachableWhenThePickerIsScaledToFit() throws {
        // Enough sets to wrap, so the mode shrinks the whole picker. Hit-testing has to
        // take the scale off as well as the position.
        let pack = try ContentPack.shipped()
        let picker = SpokenSetPicker(sets: pack.spokenSets + pack.spokenSets)
        picker.setScale(0.7)
        picker.position = CGPoint(x: 683, y: 300)

        for card in picker.cards {
            var picked: SpokenSet?
            picker.onPick = { picked = $0 }
            let scenePoint = CGPoint(x: picker.position.x + card.position.x * 0.7,
                                     y: picker.position.y + card.position.y * 0.7)
            XCTAssertTrue(picker.handleTap(at: scenePoint), "\(card.set.id) is not reachable")
            XCTAssertEqual(picked?.id, card.set.id)
        }
    }

    func testHeroCardsAreReachableWhereTheySit() throws {
        let pack = try ContentPack.shipped()
        let picker = HeroPicker(heroes: pack.heroes, language: pack.language)

        for card in picker.cards {
            var picked: Hero?
            picker.onPick = { picked = $0 }
            XCTAssertTrue(picker.handleTap(at: card.position), "\(card.hero.id) is not reachable")
            XCTAssertEqual(picked?.id, card.hero.id)
        }
    }

    // MARK: The shipped pack

    func testEverySetCarriesASymbolTheAppCanDraw() throws {
        let pack = try ContentPack.shipped()
        for set in pack.spokenSets {
            XCTAssertNotNil(SetSymbol(rawValue: set.symbol),
                            "\(set.id) asks for a symbol called '\(set.symbol)', which nothing draws")
        }
    }

    func testNoTwoSetsShareASymbol() throws {
        // The symbol is the whole label. Two cards with the same shape on them are two
        // cards a child cannot tell apart.
        let pack = try ContentPack.shipped()
        let symbols = pack.spokenSets.map(\.symbol)
        XCTAssertEqual(Set(symbols).count, symbols.count, "two sets share a symbol: \(symbols)")
    }

    func testEverySetHasEnoughLinesToBeWorthOpening() throws {
        let pack = try ContentPack.shipped()
        for set in pack.spokenSets {
            XCTAssertGreaterThanOrEqual(set.lines.count, 3, "\(set.id) is barely a set")
            for line in set.lines {
                XCTAssertGreaterThan(RepeatJudge.wordCount(of: line.text), 1,
                                     "\(set.id)/\(line.id) is too short to repeat")
            }
        }
    }

    func testTheOwlHasSomethingToSayAtEveryPointOfTheTurn() throws {
        let pack = try ContentPack.shipped()
        // Without any one of these the mode still runs, but a child gets silence where
        // the owl should have spoken.
        for group in [PhraseGroup.repeatInvite, .praise, .nudge, .setAgain] {
            XCTAssertFalse(pack.phrases[group]?.isEmpty ?? true,
                           "the pack has no \(group.rawValue) lines")
        }
    }

    func testASetWithoutASymbolStillGetsACard() {
        let set = decode(SpokenSet.self, [
            "id": "s", "kind": "rhyme", "title": "T",
            "lines": [["id": "l1", "text": "One two three."]]
        ])
        XCTAssertNotNil(SetSymbol(rawValue: set.symbol))
    }
}
