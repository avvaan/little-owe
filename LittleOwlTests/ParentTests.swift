import XCTest
@testable import LittleOwl

/// The parental gate and the settings behind it.
///
/// Two things matter here and neither is about SwiftUI: that a small child cannot get
/// through the gate, and that a parent's choice survives being written down and read
/// back — including the choice that means "all of them", which has no obvious storage.
final class ParentTests: XCTestCase {

    private func settings() -> ParentSettings {
        let suite = UserDefaults(suiteName: "ParentTests-\(UUID().uuidString)")!
        return ParentSettings(defaults: suite)
    }

    // MARK: The gate

    func testTheSumIsAlwaysPastWhatASmallChildCanCount() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<500 {
            let challenge = GateChallenge.make(using: &generator)
            // Both hands, and then some: nothing here is reachable by counting fingers.
            XCTAssertGreaterThan(challenge.answer, 10)
            // And it stays inside what a grown-up does without pausing.
            XCTAssertLessThanOrEqual(challenge.answer, 30)
            // A one-digit operand on the left would invite counting up from it.
            XCTAssertGreaterThanOrEqual(challenge.left, 11)
            XCTAssertGreaterThanOrEqual(challenge.right, 4)
        }
    }

    func testEveryAnswerIsTwoDigits() {
        // The keypad judges the attempt on the second digit, so a one-digit answer would
        // never be checked at all.
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<200 {
            let challenge = GateChallenge.make(using: &generator)
            XCTAssertEqual(String(challenge.answer).count, 2)
        }
    }

    func testTheGateTakesTheRightNumberAndNothingElse() {
        let challenge = GateChallenge(left: 13, right: 9)
        XCTAssertEqual(challenge.answer, 22)
        XCTAssertTrue(challenge.accepts("22"))
        XCTAssertTrue(challenge.accepts(" 22 "))
        XCTAssertFalse(challenge.accepts("23"))
        XCTAssertFalse(challenge.accepts("2"))
        XCTAssertFalse(challenge.accepts(""))
        XCTAssertFalse(challenge.accepts("twenty two"))
    }

    func testTheHoldIsTheBriefsThreeSeconds() {
        XCTAssertEqual(GateChallenge.holdDuration, 3)
    }

    // MARK: What is in the room

    func testEverythingIsInTheRoomUntilAParentSaysOtherwise() {
        let settings = settings()
        for object in RoomObjectID.allCases {
            XCTAssertTrue(settings.isVisible(object), "\(object) starts hidden")
        }
    }

    func testAPropCanBeTakenOutAndPutBack() {
        let settings = settings()
        settings.setVisible(.book, false)
        XCTAssertFalse(settings.isVisible(.book))
        XCTAssertTrue(settings.isVisible(.lamp), "hiding one prop hid another")

        settings.setVisible(.book, true)
        XCTAssertTrue(settings.isVisible(.book))
    }

    func testTheOwlCannotBeTurnedOff() {
        // It is not a prop, it is the app. Tapping it is also the way back from every
        // mode, so a room without it is a room a child can get stuck in.
        let settings = settings()
        settings.setVisible(.owl, false)
        XCTAssertTrue(settings.isVisible(.owl))
        XCTAssertFalse(settings.hiddenObjects.contains(.owl))
    }

    func testHidingIsStoredAsTheHiddenSetSoNewPropsArriveTurnedOn() {
        // Storing the visible set instead would mean a prop added in a later version is
        // silently missing for every family that ever opened this screen.
        let settings = settings()
        settings.setVisible(.book, false)
        XCTAssertEqual(settings.hiddenObjects, [.book])
    }

    // MARK: What is on the lamp

    func testNoChoiceMeansEverySetIsOnTheLamp() throws {
        let pack = try ContentPack.shipped()
        let settings = settings()
        XCTAssertNil(settings.enabledSpokenSetIDs)
        XCTAssertEqual(settings.spokenSets(from: pack).count, pack.spokenSets.count)
        for set in pack.spokenSets {
            XCTAssertTrue(settings.isEnabled(set))
        }
    }

    func testTurningOneSetOffLeavesTheRestOn() throws {
        // "All of them" is stored as nothing at all, so the first change has to write out
        // the whole selection or every other set would vanish with it.
        let pack = try ContentPack.shipped()
        let settings = settings()
        let first = try XCTUnwrap(pack.spokenSets.first)

        settings.setEnabled(first, false, in: pack)

        XCTAssertFalse(settings.isEnabled(first))
        XCTAssertEqual(settings.spokenSets(from: pack).count, pack.spokenSets.count - 1)
        for set in pack.spokenSets.dropFirst() {
            XCTAssertTrue(settings.isEnabled(set), "\(set.id) was turned off as well")
        }
    }

    func testAParentCanTurnEverySetOff() throws {
        let pack = try ContentPack.shipped()
        let settings = settings()
        for set in pack.spokenSets {
            settings.setEnabled(set, false, in: pack)
        }
        XCTAssertTrue(settings.spokenSets(from: pack).isEmpty)
    }

    // MARK: Captions and volume

    func testCaptionsAreOnToStartWith() {
        XCTAssertTrue(settings().captionsEnabled)
    }

    func testVolumeStartsFullAndIsClampedBothWays() {
        let settings = settings()
        XCTAssertEqual(settings.voiceVolume, 1)

        settings.voiceVolume = 1.8
        XCTAssertEqual(settings.voiceVolume, 1)

        settings.voiceVolume = -0.4
        XCTAssertEqual(settings.voiceVolume, 0)

        settings.voiceVolume = 0.35
        XCTAssertEqual(settings.voiceVolume, 0.35, accuracy: 0.0001)
    }

    // MARK: Reset

    func testResetPutsEverySettingBack() throws {
        let pack = try ContentPack.shipped()
        let settings = settings()

        settings.setVisible(.window, false)
        settings.setEnabled(try XCTUnwrap(pack.spokenSets.first), false, in: pack)
        settings.captionsEnabled = false
        settings.voiceVolume = 0.2

        settings.resetToDefaults()

        XCTAssertTrue(settings.isVisible(.window))
        XCTAssertNil(settings.enabledSpokenSetIDs)
        XCTAssertTrue(settings.captionsEnabled)
        XCTAssertEqual(settings.voiceVolume, 1)
    }

    func testSettingsSurviveBeingReadBackByANewInstance() {
        // A parent who changes something and closes the app has changed it.
        let suite = UserDefaults(suiteName: "ParentTests-\(UUID().uuidString)")!
        let first = ParentSettings(defaults: suite)
        first.setVisible(.blocks, false)
        first.captionsEnabled = false
        first.voiceVolume = 0.5

        let second = ParentSettings(defaults: suite)
        XCTAssertFalse(second.isVisible(.blocks))
        XCTAssertFalse(second.captionsEnabled)
        XCTAssertEqual(second.voiceVolume, 0.5, accuracy: 0.0001)
    }

    // MARK: Every prop a parent is offered is a prop that exists

    func testTheSettingsScreenOffersExactlyTheRoomsProps() {
        // The screen lists RoomObjectID minus the owl. If a prop is ever added without a
        // parent-facing name, this catches it before a family sees a blank row.
        for object in RoomObjectID.allCases {
            XCTAssertFalse(object.parentName.isEmpty, "\(object) has no parent-facing name")
            XCTAssertFalse(object.modeDescription.isEmpty, "\(object) has no mode description")
        }
    }
}
