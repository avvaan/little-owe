import SpriteKit

/// The seam between the owl's behaviour and the owl's artwork.
///
/// `PlaceholderOwlRig` draws vector shapes today. When the artist delivers, a
/// `RiveOwlRig` implements the same four members by poking inputs on a Rive state
/// machine, and no behaviour code changes. Nothing above this protocol may know how
/// the owl is drawn.
protocol OwlRig: AnyObject {

    /// Added to the scene by `OwlNode`. Laid out so that (0, 0) is between the owl's feet.
    var node: SKNode { get }

    /// Roughly how tall the owl stands, in design points. Used for hit areas and for
    /// working out where to land after a hop.
    var standingHeight: CGFloat { get }

    /// Enter a sustained or one-shot state. Implementations must be safe to call with
    /// the state that is already current.
    func enter(_ state: OwlState)

    /// 0 = beak closed, 1 = wide open. Driven from the audio envelope while speaking.
    func setMouthOpenness(_ openness: CGFloat)

    /// Plays over the current state without disturbing it.
    func play(_ accent: OwlAccent)
}
