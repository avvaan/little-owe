import SpriteKit
import XCTest
@testable import LittleOwl

/// What the resting owl does with itself.
///
/// The look of a move is not testable here and is not meant to be — it is artwork, and
/// it is judged by watching it. What is testable is the thing that decides a character
/// from a loop: that the moves keep coming, that they vary, and that they stop when the
/// owl has something else to do.
final class OwlTests: XCTestCase {

    // MARK: The choreography

    func testNeverTheSameMoveTwiceRunning() {
        var generator = SeededGenerator(seed: 0xC0FFEE)
        var choreography = OwlIdleChoreography()

        var previous = choreography.next(using: &generator).accent
        for _ in 0..<2_000 {
            let beat = choreography.next(using: &generator)
            XCTAssertNotEqual(beat.accent, previous, "two of the same in a row reads as a tic")
            previous = beat.accent
        }
    }

    func testEveryMoveTurnsUp() {
        var generator = SeededGenerator(seed: 7)
        var choreography = OwlIdleChoreography()

        var seen = Set<String>()
        for _ in 0..<600 {
            seen.insert(String(describing: choreography.next(using: &generator).accent))
        }

        // A move with a weight nobody ever rolls is artwork paid for and never shown.
        for accent in ["blink", "headTilt", "bobble", "ruffle", "headTurn", "peer", "doubleTake"] {
            XCTAssertTrue(seen.contains { $0.hasPrefix(accent) }, "\(accent) never came up in 600 moves")
        }
    }

    func testTheSidesAlternate() {
        var generator = SeededGenerator(seed: 99)
        var choreography = OwlIdleChoreography()

        var sides: [OwlTurn] = []
        for _ in 0..<400 {
            switch choreography.next(using: &generator).accent {
            case .headTurn(let side), .peer(let side), .doubleTake(let side):
                sides.append(side)
            default:
                break
            }
        }

        XCTAssertGreaterThan(sides.count, 20, "not enough turning moves to judge")
        for (index, side) in sides.enumerated() where index > 0 {
            XCTAssertEqual(side, sides[index - 1].opposite,
                           "an owl that only looks one way looks broken")
        }
    }

    func testThePausesStayInTheirBand() {
        var generator = SeededGenerator(seed: 4)
        var choreography = OwlIdleChoreography()

        for _ in 0..<1_000 {
            let pause = choreography.next(using: &generator).pause
            // Below two seconds the owl is twitching; above sixteen it has stopped.
            XCTAssertGreaterThanOrEqual(pause, 2.0)
            XCTAssertLessThanOrEqual(pause, 16.0)
        }
    }

    func testTheWeightsKeepTheBigMovesRare() {
        var generator = SeededGenerator(seed: 1234)
        var choreography = OwlIdleChoreography()

        var blinks = 0
        var doubleTakes = 0
        for _ in 0..<4_000 {
            switch choreography.next(using: &generator).accent {
            case .blink: blinks += 1
            case .doubleTake: doubleTakes += 1
            default: break
            }
        }

        // The joke stops being funny somewhere around the fortieth time.
        XCTAssertGreaterThan(blinks, doubleTakes * 3)
    }

    // MARK: The owl driving it

    func testARestingOwlKeepsMoving() {
        let rig = SpyRig()
        let owl = OwlNode(rig: rig, randomness: SeededGenerator(seed: 11))

        // Two minutes of a child looking at the screen and touching nothing. The sleepy
        // pose would end the moves, so this stops just short of it.
        owl.sleepyAfter = .greatestFiniteMagnitude
        tick(owl, until: 120)

        // At the slowest the repertoire allows — sixteen seconds a move — two minutes is
        // still seven or eight of them.
        XCTAssertGreaterThan(rig.accents.count, 7, "the owl went still")
    }

    func testTheFirstMoveWaitsForIt() {
        let rig = SpyRig()
        let owl = OwlNode(rig: rig, randomness: SeededGenerator(seed: 11))

        // Whatever the shortest pause in the repertoire is, nothing happens inside it —
        // an owl that blinks on the first frame of the app has been startled.
        tick(owl, until: 2.0)
        XCTAssertTrue(rig.accents.isEmpty)
    }

    func testAnOwlWithSomethingToDoStopsFidgeting() {
        let rig = SpyRig()
        let owl = OwlNode(rig: rig, randomness: SeededGenerator(seed: 3))
        owl.sleepyAfter = .greatestFiniteMagnitude

        owl.transition(to: .listening)
        tick(owl, until: 120)

        XCTAssertTrue(rig.accents.isEmpty, "the owl looked away while the child was talking")
    }

    func testTheOwlPicksItUpAgainAfterwards() {
        let rig = SpyRig()
        let owl = OwlNode(rig: rig, randomness: SeededGenerator(seed: 3))
        owl.sleepyAfter = .greatestFiniteMagnitude

        owl.transition(to: .speaking)
        tick(owl, until: 60)
        XCTAssertTrue(rig.accents.isEmpty)

        owl.transition(to: .idle)
        tick(owl, from: 60, until: 180)
        XCTAssertGreaterThan(rig.accents.count, 5, "the owl never woke back up")
    }

    func testASleepyOwlIsLeftAlone() {
        let rig = SpyRig()
        let owl = OwlNode(rig: rig, randomness: SeededGenerator(seed: 5))
        owl.sleepyAfter = 10

        tick(owl, until: 200)
        let whileAwake = rig.accents.count

        XCTAssertEqual(owl.state, .sleepy)
        // Whatever it managed before dropping off, it is not still swivelling three
        // minutes later.
        tick(owl, from: 200, until: 400)
        XCTAssertEqual(rig.accents.count, whileAwake)
    }

    // MARK: Helpers

    /// Sixty frames a second, which is what the scene hands it.
    private func tick(_ owl: OwlNode, from start: TimeInterval = 0, until end: TimeInterval) {
        var now = start
        while now < end {
            owl.update(currentTime: now)
            now += 1.0 / 60.0
        }
    }
}

/// Records what the owl asked for without drawing any of it.
private final class SpyRig: OwlRig {
    let node = SKNode()
    let character: Character = .owl
    var standingHeight: CGFloat { 400 }

    private(set) var states: [OwlState] = []
    private(set) var accents: [OwlAccent] = []

    func enter(_ state: OwlState) { states.append(state) }
    func setMouthOpenness(_ openness: CGFloat) {}
    func play(_ accent: OwlAccent) { accents.append(accent) }
}

/// A dice cup that rolls the same way every run, so a failure here is a real one rather
/// than a seed that happened to be unlucky.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed &* 2_685_821_657_736_338_717 &+ 1 }

    mutating func next() -> UInt64 {
        // SplitMix64. Small, and its output is good enough that a test which passes
        // here is not passing because the generator is lopsided.
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
