import CoreGraphics

/// A mode that takes the room over.
///
/// All of them work the same way: a dimming layer goes up, the mode's own overlay sits
/// above it, and the room behind is no longer something the child can see — so the scene
/// must stop routing taps to it. Tapping the owl is always the way back, and a mode may
/// nominate one prop as "again" while it is offering one.
///
/// The protocol exists so `RoomScene` has one routing rule rather than one per mode.
protocol RoomMode: AnyObject {

    var isRunning: Bool { get }

    /// True if the mode's own overlay took the tap. `point` is in scene coordinates.
    func handleTap(at point: CGPoint) -> Bool

    /// The prop that means "again" right now, if the mode is offering one. The scene
    /// lifts it above the dimming and lets it glow while this is non-nil.
    var againProp: RoomObjectID? { get }

    func againTapped()

    /// Tear down and give the room back.
    func leave()
}

/// Where a running mode's layers sit, above everything the room draws.
///
/// Shared rather than per-mode so the scene can lift a prop to exactly the right place
/// without knowing which mode is running.
enum ModeLayer {
    /// The wash and vignette that put the room behind the mode without hiding it.
    static let backdrop: CGFloat = 200
    /// The owl stays lit: it is doing the talking.
    static let owl: CGFloat = 210
    /// A prop raised above the dimming because tapping it means "again".
    static let offer: CGFloat = 215
    /// Cards, pages, captions.
    static let overlay: CGFloat = 220
}
