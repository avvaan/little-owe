import SpriteKit
import XCTest
@testable import LittleOwl

/// Every painting the app asks for is in the bundle and loads.
///
/// This file exists because it did not, and the cost was a child being handed an iPad
/// showing a giant red cross where the room should be. SpriteKit draws that when a
/// texture is missing, and nothing before the device said a word: the build was green,
/// the art check passed — it compares the files on disk to what the export script
/// produces, and the file was correct — and the upload succeeded.
///
/// The gap was between "the file is in the repository" and "the app can load it". The
/// room is the one JPEG among PNGs, and `imageNamed:` assumes `.png` for a loose bundle
/// file. So these tests load, rather than look for.
final class ArtTests: XCTestCase {

    /// Everything `RoomBuilder`, `WindowNode` and the owl rig ask for by name. The room
    /// cannot be assembled without any of them.
    private let required = [
        "room_bg",
        "patch_book",
        "block_a", "block_b", "block_c",
        "window_woodwork",
        "window_sky_night",
        "owl_base"
    ]

    func testEveryPaintingTheRoomNeedsLoads() {
        for name in required {
            XCTAssertNotNil(ArtTexture.url(named: name),
                            "\(name) is not in the bundle at all")
            let texture = ArtTexture.texture(named: name)
            XCTAssertNotNil(texture, "\(name) is in the bundle but did not load")
            // A texture that loaded but has no pixels would draw as nothing, which is
            // the quiet version of the same bug.
            XCTAssertGreaterThan(texture?.size().width ?? 0, 1, name)
            XCTAssertGreaterThan(texture?.size().height ?? 0, 1, name)
        }
    }

    func testTheRoomIsTheShapeTheLayoutExpects() {
        // The room is stretched to `designSize`, so a painting of the wrong aspect would
        // not fail to load - it would quietly distort.
        let room = try? XCTUnwrap(ArtTexture.texture(named: "room_bg"))
        guard let room else { return }

        let painted = room.size().width / room.size().height
        let design = RoomLayout.designSize.width / RoomLayout.designSize.height
        XCTAssertEqual(painted, design, accuracy: 0.02,
                       "the room painting is \(painted) wide to tall, the layout assumes \(design)")
    }

    func testTheOptionalOwlFramesEitherLoadOrAreAbsent() {
        // A frame that is present but unloadable is the bug this file is about. A frame
        // that is simply not painted yet is fine and the rig falls back to the base.
        for name in ["owl_blink", "owl_sleepy", "owl_happy", "owl_listen",
                     "owl_talk_half", "owl_talk_wide", "owl_turn_left", "owl_turn_right"] {
            guard ArtTexture.exists(name) else { continue }
            XCTAssertNotNil(ArtTexture.texture(named: name), "\(name) is present but did not load")
        }
    }

    func testEverySkyThatExistsLoads() {
        for time in TimeOfDay.allCases {
            guard WindowNode.hasPaintedSky(for: time) else { continue }
            XCTAssertNotNil(ArtTexture.texture(named: "window_sky_\(time.rawValue)"),
                            "the \(time.rawValue) sky is present but did not load")
        }
    }

    /// The loader's own rule, stated as a test: the extension is not guessed.
    func testAPaintingIsFoundWhateverItWasSavedAs() {
        // room_bg is the JPEG, block_a is a PNG. Both are asked for without an
        // extension and both must come back.
        XCTAssertEqual(ArtTexture.url(named: "room_bg")?.pathExtension, "jpg")
        XCTAssertEqual(ArtTexture.url(named: "block_a")?.pathExtension, "png")
        XCTAssertNil(ArtTexture.url(named: "no_such_painting"))
        XCTAssertNil(ArtTexture.texture(named: "no_such_painting"))
    }
}
