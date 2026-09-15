import SpriteKit
import XCTest
@testable import LittleOwl

/// A second animal in the attic.
///
/// The thing worth testing is not that the puppy looks right — that is judged by
/// looking at it — but that a character whose paintings have not arrived cannot break
/// the room, and that swapping does not lose whatever the animal was in the middle of.
final class CharacterTests: XCTestCase {

    func testTheOwlIsAlwaysThere() {
        // It is the app. A build where this is false is a build with no character in it.
        XCTAssertTrue(Character.owl.isAvailable, "the owl's base painting is not in the bundle")
        XCTAssertEqual(Character.fallback, .owl)
        XCTAssertEqual(Character.available.first, .owl, "the owl is always offered first")
    }

    func testOnlyCharactersWithPaintingsAreOffered() {
        for character in Character.available {
            XCTAssertNotNil(ArtTexture.texture(named: "\(character.artPrefix)_base"),
                            "\(character.name) is offered but has no base painting")
        }
    }

    func testAStoredCharacterWithNoPaintingsFallsBack() {
        let suite = UserDefaults(suiteName: "CharacterTests-\(UUID().uuidString)")!
        let settings = ParentSettings(defaults: suite)

        // What a downgrade looks like: the choice was made in a build that had the
        // paintings, and this build does not.
        suite.set("dog", forKey: "parent.character")
        if Character.dog.isAvailable {
            XCTAssertEqual(settings.character, .dog)
        } else {
            XCTAssertEqual(settings.character, .owl, "a character with no art must not be chosen")
        }

        // And plain rubbish, which is what a hand-edited plist looks like.
        suite.set("badger", forKey: "parent.character")
        XCTAssertEqual(settings.character, .owl)
    }

    func testTheRoomStartsAsTheOwl() {
        let suite = UserDefaults(suiteName: "CharacterTests-\(UUID().uuidString)")!
        XCTAssertEqual(ParentSettings(defaults: suite).character, .owl,
                       "a fresh install must open on the owl")
    }

    // MARK: Swapping

    func testSwappingKeepsThePose() {
        let owl = OwlNode(rig: SpyRig(character: .owl))
        owl.transition(to: .listening)

        let dog = SpyRig(character: .dog)
        owl.wear(dog)

        // A child who swaps mid-sentence gets the same character mid-sentence.
        XCTAssertEqual(owl.state, .listening)
        XCTAssertEqual(dog.states.last, .listening,
                       "the new rig was not told what it had walked into")
    }

    func testSwappingReplacesTheArtworkAndNothingElse() {
        let first = SpyRig(character: .owl)
        let owl = OwlNode(rig: first)
        let before = owl.position

        let second = SpyRig(character: .dog)
        owl.wear(second)

        XCTAssertNil(first.node.parent, "the old paintings are still in the scene")
        XCTAssertNotNil(second.node.parent, "the new paintings were never added")
        XCTAssertEqual(owl.position, before, "the animal moved when it should only have changed")
    }

    // MARK: The badge in the corner

    func testTheBadgeIsWhereEveryIPadCanSeeIt() {
        // The room is authored at 1366x1024 and drawn with .aspectFill. The narrowest
        // iPad this ships to crops 63 points off the top, so a target that runs past
        // y = 961 is a target some children cannot reach.
        let centre = CharacterPicker.centre
        let half = RoomLayout.minimumTapTarget / 2

        XCTAssertLessThanOrEqual(centre.y + half, 961, "the badge is cropped on a narrow iPad")
        XCTAssertLessThanOrEqual(centre.x + half, RoomLayout.designSize.width - 20)
        XCTAssertGreaterThanOrEqual(centre.y - half, 0)
    }

    func testTheBadgeDoesNotSitOnTheWindow() {
        let window = CGRect(origin: CGPoint(x: RoomLayout.windowCentre.x - RoomLayout.windowTapSize.width / 2,
                                            y: RoomLayout.windowCentre.y - RoomLayout.windowTapSize.height / 2),
                            size: RoomLayout.windowTapSize)
        let badge = CGRect(x: CharacterPicker.centre.x - RoomLayout.minimumTapTarget / 2,
                           y: CharacterPicker.centre.y - RoomLayout.minimumTapTarget / 2,
                           width: RoomLayout.minimumTapTarget, height: RoomLayout.minimumTapTarget)

        XCTAssertFalse(window.intersects(badge),
                       "the badge overlaps the window: one of them would swallow the other's taps")
    }

    func testTheBadgeOffersTheOtherAnimal() {
        let picker = CharacterPicker(offering: .owl)
        XCTAssertEqual(picker.offered, .owl)

        var picked: Character?
        picker.onPick = { picked = $0 }
        picker.acknowledgeTap()
        XCTAssertEqual(picked, .owl, "tapping the badge did not offer what it was showing")
    }

    func testTheBadgeHidesWhenThereIsNobodyElse() {
        let picker = CharacterPicker(offering: .owl)
        // With only the owl painted, there is nobody to offer once the owl is on the
        // perch, and a badge offering nothing is worse than no badge.
        picker.nowOnThePerch(.owl)
        if Character.available.count == 1 {
            XCTAssertTrue(picker.isHidden)
        } else {
            XCTAssertFalse(picker.isHidden)
            XCTAssertNotEqual(picker.offered, .owl)
        }
    }
}

/// Records what it was asked to do and paints nothing.
private final class SpyRig: OwlRig {
    let node = SKNode()
    let character: Character
    var standingHeight: CGFloat { 400 }

    private(set) var states: [OwlState] = []

    init(character: Character) { self.character = character }

    func enter(_ state: OwlState) { states.append(state) }
    func setMouthOpenness(_ openness: CGFloat) {}
    func play(_ accent: OwlAccent) {}
}
