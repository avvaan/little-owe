import Foundation

/// The owl's six moods. Everything the app ever asks the character to do goes through
/// this enum, so swapping the placeholder rig for the final Rive file is a one-line
/// change in `OwlNode`.
enum OwlState: String, CaseIterable {

    /// Breathing, blinking, the occasional head tilt. The resting state.
    case idle

    /// Ear tufts up, leaning in. Shown while the microphone is live.
    case listening

    /// Eyes closed, gentle sway, soft hum. Exists to cover any processing delay so the
    /// child never sees a frozen owl.
    case thinking

    /// Beak driven by the audio envelope.
    case speaking

    /// A bounce. Praise, and the answer to being tapped.
    case happy

    /// Yawn and droop after a long idle. Purely decorative — any tap wakes the owl,
    /// and nothing in the app is gated behind it.
    case sleepy

    /// Whether the state loops until something else interrupts it.
    var isSustained: Bool {
        switch self {
        case .idle, .listening, .thinking, .speaking, .sleepy: return true
        case .happy: return false
        }
    }
}

/// Which way the owl is looking. The owl's own left, which is the screen's left too:
/// the bird faces the child.
enum OwlTurn: Equatable {
    case left
    case right

    var opposite: OwlTurn { self == .left ? .right : .left }

    /// +1 turns the bird anticlockwise, which on screen is towards its left.
    var sign: CGFloat { self == .left ? 1 : -1 }
}

/// Short accents that play over whatever state is current, rather than replacing it.
enum OwlAccent: Equatable {
    case blink

    /// A small lean. The quiet one.
    case headTilt

    /// The swivel: the head goes round to one side, holds, and comes back. An owl's
    /// party trick, and the move a child waits for.
    case headTurn(OwlTurn)

    /// Looks one way, then snaps the other — as though something went past.
    case doubleTake(OwlTurn)

    /// The sideways lean, held long enough to be funny: the owl tips its whole head
    /// over and studies the room from there.
    case peer(OwlTurn)

    /// Two quick bobs, like a bird deciding whether to come closer.
    case bobble

    /// A shiver through the feathers, and they settle.
    case ruffle

    case yawn

    /// A quick squash. The instant answer to being touched, small enough that it does
    /// not disturb whatever the owl was already doing.
    case nudge
}
