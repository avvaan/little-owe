import SpriteKit

/// Anything in the room a child can touch.
///
/// The scene owns hit testing rather than using `isUserInteractionEnabled` per node:
/// with padded tap targets the boxes deliberately overlap the artwork of neighbours,
/// and a single ordered sweep gives predictable, debuggable results.
protocol Tappable: SKNode {
    var tapID: RoomObjectID { get }

    /// `point` is in the parent's (scene's) coordinate space.
    func containsPoint(inParent point: CGPoint) -> Bool

    /// Immediate sound-and-motion response, before any mode work begins.
    func acknowledgeTap()

    /// The padded target in the parent's space. Used by the debug overlay.
    var hitAreaInParent: CGRect { get }
}
