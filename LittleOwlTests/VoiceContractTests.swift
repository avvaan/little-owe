import AVFoundation
import XCTest
@testable import LittleOwl

/// The one promise the owl's voice makes to every mode that uses it.
///
/// `OwlVoice.onFinished` is documented as "main queue, once, when the line has finished
/// — or been stopped", and everything the owl says is built on it: each caller says a
/// line and decides what happens next when that fires. Story pages turn on it, prayers
/// advance on it, word games ask the next one on it, the window opens the child's turn
/// on it, the basket lays out its cards on it, and the tap-to-choose row reads each card
/// aloud on it.
///
/// So a line that never reports finishing is not a missed sound. It is a mode frozen
/// where it stands, with nothing on screen and no way out but tapping the owl — which is
/// what a child sees as the owl starting to ask something and then switching off.
///
/// `VoicePlayer.play(contentsOf:)` used to return `true` whether or not the engine
/// started. Nothing was scheduled, so no completion ever came, and `OwlVoice` sat with
/// `isSpeaking` true for the rest of the session.
final class VoiceContractTests: XCTestCase {

    private func pack() throws -> ContentPack {
        try XCTUnwrap(try? ContentLoader.load())
    }

    // MARK: The player

    /// A file that is not audio at all. The point is the answer, not the failure: a
    /// caller told `false` knows it has to say the line some other way.
    func testThePlayerSaysNoWhenItCannotPlay() throws {
        let notAudio = FileManager.default.temporaryDirectory
            .appendingPathComponent("not-audio-\(UUID().uuidString).m4a")
        try Data("this is not a sound".utf8).write(to: notAudio)
        defer { try? FileManager.default.removeItem(at: notAudio) }

        let player = VoicePlayer()
        var finished = false
        player.onFinished = { finished = true }

        XCTAssertFalse(player.play(contentsOf: notAudio),
                       "the player claimed to be playing a file that is not audio")
        XCTAssertFalse(player.isPlaying)
        XCTAssertFalse(finished, "nothing played, so nothing finished")
    }

    func testAMissingFileIsRefusedRatherThanSwallowed() {
        let player = VoicePlayer()
        let nowhere = URL(fileURLWithPath: "/no/such/clip.m4a")
        XCTAssertFalse(player.play(contentsOf: nowhere))
        XCTAssertFalse(player.isPlaying)
    }

    // MARK: The voice

    /// Whatever happens underneath — a recording, the synthesiser, or a refusal from
    /// both — `say` must end with the owl not speaking. A voice stuck in `isSpeaking`
    /// is a mode stuck with it, because `stop()` is the only thing that clears it and
    /// nothing calls `stop()` while a mode is waiting to be told the line ended.
    func testStopAlwaysLeavesTheOwlQuiet() throws {
        let voice = OwlVoice(pack: try pack())
        voice.say(SpokenText(id: "t", text: "Hello little one.", stem: "no-such-recording"))
        voice.stop()
        XCTAssertFalse(voice.isSpeaking, "the owl is still speaking after being stopped")
    }

    /// A line with no recording falls back to the synthesiser rather than going nowhere.
    /// This is the per-line fallback the pack depends on while it is half-recorded.
    func testALineWithNoRecordingStillGetsSaid() throws {
        let p = try pack()
        let orphan = SpokenText(id: "orphan", text: "Look at this.",
                                stem: "there-is-no-clip-called-this")
        XCTAssertNil(ContentLoader.audioURL(for: orphan, language: p.language),
                     "this test needs a line the pack really has no recording for")

        let voice = OwlVoice(pack: p)
        voice.say(orphan)
        XCTAssertTrue(voice.isUsingSynthesiser,
                      "a line with no recording has to reach the synthesiser")
        voice.stop()
    }

    /// The promise itself, end to end: ask the owl to say something and `onFinished`
    /// arrives, whichever path delivers it.
    ///
    /// This passes if the recording plays, if the synthesiser speaks, **and** if neither
    /// does and the watchdog has to report the line over — which is the whole point. A
    /// mode does not care how the line was said. It cares that it is told when to do the
    /// next thing, and before this existed there was a way for that to never happen.
    func testAskingTheOwlToSpeakAlwaysComesBack() throws {
        let voice = OwlVoice(pack: try pack())
        voice.watchdogMargin = 0.4

        let spoken = expectation(description: "the owl reported its line finished")
        voice.onFinished = { spoken.fulfill() }
        voice.say(SpokenText(id: "promise", text: "Hello.", stem: "no-such-recording"))

        wait(for: [spoken], timeout: 10)
        XCTAssertFalse(voice.isSpeaking)
    }

    /// And the rescue must not be a hair trigger. A line that is genuinely being said
    /// reports itself, once.
    func testTheLineIsReportedOnceAndOnlyOnce() throws {
        let voice = OwlVoice(pack: try pack())
        voice.watchdogMargin = 0.4

        var count = 0
        let spoken = expectation(description: "finished")
        voice.onFinished = {
            count += 1
            if count == 1 { spoken.fulfill() }
        }
        voice.say(SpokenText(id: "once", text: "Hello.", stem: "no-such-recording"))
        wait(for: [spoken], timeout: 10)

        // Long enough for a watchdog that had not been cancelled to fire again.
        let settled = expectation(description: "settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { settled.fulfill() }
        wait(for: [settled], timeout: 5)

        XCTAssertEqual(count, 1, "the line reported finishing more than once")
    }

    /// Every mode that speaks drives itself from `onFinished`. Listed here so that a new
    /// one is a deliberate addition rather than a surprise — and so the count in the
    /// doc comment above stays true.
    func testTheModesThatDependOnThisAreTheOnesWeThinkTheyAre() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // LittleOwlTests
            .deletingLastPathComponent()      // repository root
            .appendingPathComponent("LittleOwl/Modes")

        // Reads the source tree, so it only means anything where the source is: a test
        // bundle running somewhere else skips rather than failing for the wrong reason.
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        try XCTSkipIf(names.isEmpty, "no source tree at \(root.path) to read")

        var dependent: [String] = []
        for name in names where name.hasSuffix(".swift") {
            let text = (try? String(contentsOf: root.appendingPathComponent(name),
                                    encoding: .utf8)) ?? ""
            if text.contains("voice.onFinished = ") { dependent.append(name) }
        }

        XCTAssertEqual(
            Set(dependent),
            ["StoryMode.swift", "SpokenSetMode.swift", "WordGameMode.swift",
             "WhyMode.swift", "WonderMode.swift",
             // Not a mode: the tap-to-choose row borrows the callback to read each card
             // aloud and hands it back when it is done. It hangs on this too.
             "SpokenChoices.swift"],
            "the set of modes that hang on a line finishing has changed — if a mode was "
            + "added, it inherits everything this file is about")
    }
}
