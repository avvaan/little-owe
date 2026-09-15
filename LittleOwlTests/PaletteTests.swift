import SpriteKit
import XCTest
@testable import LittleOwl

/// The light the code lays over the painting.
///
/// This exists because of a bug that reached a real iPad and made the room almost
/// black between nine at night and five in the morning. The wash is the one piece of
/// the room that nothing could see: `docs/preview/` composited the painting and the
/// sprites and stopped there, the art check compares exported files rather than
/// rendered frames, and no test looked at `Palette` at all. It was invisible to every
/// check in the project and obvious within one second of opening the app at night.
///
/// So these tests do the blend arithmetic themselves and assert the room is still
/// there afterwards. They are a mirror of what SpriteKit does rather than SpriteKit —
/// the same caveat `tools/simulate_turn_detection.py` carries — but the failure they
/// catch is not a subtlety of rendering. It is a wash that multiplies the room by
/// nearly zero, which is wrong under any correct implementation of the formula.
final class PaletteTests: XCTestCase {

    /// A mid-tone of the attic's warm wood, measured off `room_bg.jpg` rather than
    /// invented: the mean pixel of the painting is about this.
    private let wood = (r: 0.55, g: 0.45, b: 0.36)

    /// What one pixel of the room becomes once the wash is over it.
    ///
    /// Only the blend modes the palette actually uses are implemented. A new one has to
    /// be added here deliberately, which is the point — the bug was a blend mode whose
    /// alpha behaves backwards being dropped in beside three whose alpha does not.
    private func washed(_ time: TimeOfDay) -> (r: Double, g: Double, b: Double) {
        let spec = Palette.ambientWash(for: time)
        var sr: CGFloat = 0, sg: CGFloat = 0, sb: CGFloat = 0, sa: CGFloat = 0
        spec.color.getRed(&sr, green: &sg, blue: &sb, alpha: &sa)
        let a = Double(spec.alpha)
        let src = (r: Double(sr), g: Double(sg), b: Double(sb))

        switch spec.blend {
        case .add:
            return (min(1, wood.r + src.r * a),
                    min(1, wood.g + src.g * a),
                    min(1, wood.b + src.b * a))
        case .alpha:
            return (wood.r * (1 - a) + src.r * a,
                    wood.g * (1 - a) + src.g * a,
                    wood.b * (1 - a) + src.b * a)
        case .multiply, .multiplyX2, .multiplyX2Alpha:
            // SpriteKit premultiplies the source colour by the node's alpha. Written out
            // rather than left to be assumed, because assuming otherwise is the bug.
            let doubled = spec.blend == .multiply ? 1.0 : 2.0
            return (wood.r * src.r * a * doubled,
                    wood.g * src.g * a * doubled,
                    wood.b * src.b * a * doubled)
        default:
            XCTFail("\(time) uses a blend mode PaletteTests does not model: \(spec.blend)")
            return wood
        }
    }

    private func luminance(_ c: (r: Double, g: Double, b: Double)) -> Double {
        0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
    }

    /// The one that failed. A wash is light over a painting, not a replacement for it.
    func testNoTimeOfDayPutsTheRoomOut() {
        let bare = luminance(wood)

        for time in TimeOfDay.allCases {
            let after = luminance(washed(time))
            let ratio = after / bare

            XCTAssertGreaterThan(
                ratio, 0.6,
                "\(time.rawValue) leaves the room at \(Int(ratio * 100))% of the painting — "
                + "a child cannot see a room that is not there")
            XCTAssertLessThan(
                ratio, 1.45,
                "\(time.rawValue) blows the room out to \(Int(ratio * 100))% of the painting")
        }
    }

    /// Night should be cooler than the painting, which is the entire reason it exists.
    /// It is also the check that a future tint cannot be cool by being black: a pixel
    /// with no red left in it satisfies "bluer" and fails the test above.
    func testNightIsCoolerAndTheOthersAreNot() {
        let night = washed(.night)
        XCTAssertGreaterThan(night.b / night.r, wood.b / wood.r,
                             "the night wash does not cool the room")

        for time: TimeOfDay in [.morning, .evening] {
            let warm = washed(time)
            XCTAssertLessThanOrEqual(warm.b / warm.r, wood.b / wood.r + 0.02,
                                     "\(time.rawValue) should not cool the room")
        }
    }

    /// Fading between times of day animates this node's `alpha`, so every blend used
    /// has to mean "none of it" at alpha zero. Multiply does not — at alpha zero its
    /// source is black and the room goes with it — so a dusk crossfade would dip
    /// through a black screen on the way.
    func testEveryWashFadesInFromNothing() {
        for time in TimeOfDay.allCases {
            let blend = Palette.ambientWash(for: time).blend
            XCTAssertTrue(
                blend == .add || blend == .alpha,
                "\(time.rawValue) uses \(blend), whose alpha does not run from none to all — "
                + "fading to it would pass through a black room")
        }
    }
}
