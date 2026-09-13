import XCTest
@testable import LittleOwl

/// `normalise` turns a raw RMS into the 0...1 the beak and the level meter use. It is
/// the one piece of the recorder that is pure arithmetic, and the one most likely to be
/// tuned later by somebody guessing.
final class VoiceRecorderTests: XCTestCase {

    func testSilenceIsZeroAndLoudIsOne() {
        XCTAssertEqual(VoiceRecorder.normalise(0), 0)
        XCTAssertEqual(VoiceRecorder.normalise(1.0), 1, accuracy: 0.001)
    }

    func testItStaysInRange() {
        for level in stride(from: Float(0), through: 2, by: 0.05) {
            let value = VoiceRecorder.normalise(level)
            XCTAssertGreaterThanOrEqual(value, 0)
            XCTAssertLessThanOrEqual(value, 1)
        }
    }

    func testLouderIsNeverQuieter() {
        var previous = VoiceRecorder.normalise(0)
        for level in stride(from: Float(0.001), through: 1, by: 0.01) {
            let value = VoiceRecorder.normalise(level)
            XCTAssertGreaterThanOrEqual(value, previous)
            previous = value
        }
    }

    func testAChildAtArmsLengthLandsInTheUsefulMiddle() {
        // Roughly −30 dB, which is where a small voice a foot from an iPad sits. If the
        // curve ever pushes that to 0 or 1, the beak stops moving with the words.
        let value = VoiceRecorder.normalise(0.03)
        XCTAssertGreaterThan(value, 0.2)
        XCTAssertLessThan(value, 0.9)
    }
}
