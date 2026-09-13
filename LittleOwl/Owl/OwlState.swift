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

/// Short accents that play over whatever state is current, rather than replacing it.
enum OwlAccent {
    case blink
    case headTilt
    case yawn
    /// A quick squash. The instant answer to being touched, small enough that it does
    /// not disturb whatever the owl was already doing.
    case nudge
}
