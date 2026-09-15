import Foundation

/// What the owl does when nobody is asking anything of it.
///
/// A three-year-old spends long stretches simply watching this screen, and an owl that
/// leans two degrees every eleven seconds reads as a picture rather than a bird. So the
/// resting owl has a repertoire, and this picks what comes next and how long to wait
/// before it.
///
/// Three rules do most of the work:
///
/// - **Never the same move twice running.** Two blinks in a row is a tic; a blink then
///   a swivel is a bird.
/// - **The big moves stay rare.** A double take is funny the fourth time you see it and
///   tiresome the fortieth, so the weights keep it that way.
/// - **The sides alternate.** Left, then right, then left. An owl that only ever looks
///   one way looks broken, and looking both ways is most of what makes the swivel read.
///
/// Every pause is re-rolled, so nothing settles into a rhythm a child can predict —
/// which is the difference between a character and a loop.
///
/// Kept apart from the rig on purpose: *which* move comes next is behaviour and is
/// tested; *what the move looks like* is artwork and lives in `OwlRig`.
struct OwlIdleChoreography {

    /// One thing the owl does, and how long the room stays still first.
    struct Beat: Equatable {
        let accent: OwlAccent
        let pause: TimeInterval
    }

    enum Move: CaseIterable, Equatable {
        case blink
        case tilt
        case turn
        case bobble
        case ruffle
        case peer
        case doubleTake
    }

    /// How often each move is worth seeing, and the range of quiet before it.
    ///
    /// The ranges overlap deliberately. A fixed pause per move would mean a child could
    /// learn that a long silence means the big one is coming.
    static func shape(of move: Move) -> (weight: Int, pause: ClosedRange<TimeInterval>) {
        switch move {
        case .blink:      return (34, 2.2...5.0)
        case .tilt:       return (16, 3.5...8.0)
        case .turn:       return (16, 4.0...9.0)
        case .bobble:     return (11, 5.0...10.0)
        case .ruffle:     return (8, 5.5...11.0)
        case .peer:       return (9, 7.0...14.0)
        case .doubleTake: return (6, 8.0...16.0)
        }
    }

    private var lastMove: Move?
    private var lastSide: OwlTurn = .right

    /// The side the next turning move will use. Alternating rather than rolling for it
    /// means the owl is never seen looking the same way twice running, which is exactly
    /// the thing that would make the swivel look like a stutter.
    private var nextSide: OwlTurn { lastSide.opposite }

    init() {}

    mutating func next<G: RandomNumberGenerator>(using generator: inout G) -> Beat {
        let move = Self.pick(excluding: lastMove, using: &generator)
        lastMove = move

        let shape = Self.shape(of: move)
        let pause = TimeInterval.random(in: shape.pause, using: &generator)

        let accent: OwlAccent
        switch move {
        case .blink:
            accent = .blink
        case .tilt:
            accent = .headTilt
        case .bobble:
            accent = .bobble
        case .ruffle:
            accent = .ruffle
        case .turn:
            lastSide = nextSide
            accent = .headTurn(lastSide)
        case .peer:
            lastSide = nextSide
            accent = .peer(lastSide)
        case .doubleTake:
            lastSide = nextSide
            accent = .doubleTake(lastSide)
        }

        return Beat(accent: accent, pause: pause)
    }

    /// Weighted, with the previous move taken out of the hat rather than re-rolled
    /// until it differs — a re-roll loop has no bound on how long it runs.
    static func pick<G: RandomNumberGenerator>(excluding last: Move?, using generator: inout G) -> Move {
        let options = Move.allCases.filter { $0 != last }
        let total = options.reduce(0) { $0 + shape(of: $1).weight }
        var roll = Int.random(in: 0..<total, using: &generator)
        for option in options {
            roll -= shape(of: option).weight
            if roll < 0 { return option }
        }
        // Unreachable: the weights are positive and the roll is below their sum.
        return options[options.count - 1]
    }
}

/// A dice cup the owl can be handed.
///
/// `RandomNumberGenerator` is a protocol whose existential does not conform to itself,
/// so this thin box is what lets a test give `OwlNode` a predictable one without every
/// type above it becoming generic.
struct OwlRandomness: RandomNumberGenerator {
    private var source: RandomNumberGenerator

    init(_ source: RandomNumberGenerator = SystemRandomNumberGenerator()) {
        self.source = source
    }

    mutating func next() -> UInt64 { source.next() }
}
