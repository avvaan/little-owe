import SpriteKit

/// Fixed design canvas, matching the aspect of the painted room (2336 × 1744 → 4:3).
/// The scene is authored at this size and drawn with `.aspectFill`, so on every
/// supported iPad the room fills the screen and only a little is cropped from the
/// long edge.
///
/// Every coordinate below was measured off the artwork rather than invented. The
/// measurements can be re-checked at any time with:
///
///     python3 tools/compose_room.py --grid
enum RoomLayout {

    static let designSize = CGSize(width: 1366, height: 1024)

    /// The painted room is 2336 px wide for these 1366 design points.
    static let artScale: CGFloat = 2336.0 / 1366.0

    // MARK: Tap targets

    /// The UX rule is 88 × 88 **points on the device**. With `.aspectFill` the scene is
    /// scaled down on every iPad narrower than 4:3; the worst case in the supported
    /// range is the 10th-gen iPad at 1180 × 820 pt, where
    ///   scale = max(1180/1366, 820/1024) = 0.864
    /// so 88 pt on screen needs 88 / 0.864 = 102 design points. We round well past that.
    /// `DebugOverlay` draws these rectangles so the margin can be checked on device.
    static let minimumTapTarget: CGFloat = 120

    // MARK: Props, measured from the painting

    /// The open book on the shelf. Painted into the background, so only the tap target
    /// lives here.
    static let bookCentre = CGPoint(x: 262, y: 800)
    static let bookSize   = CGSize(width: 230, height: 150)

    /// The lamp on the side table. Also painted in.
    static let lampCentre = CGPoint(x: 195, y: 551)
    static let lampSize   = CGSize(width: 190, height: 215)

    /// The round window. The glass is a separate sprite so the sky can change with the
    /// clock; the muntins sit above it as their own overlay.
    static let windowCentre = CGPoint(x: 1035, y: 724)
    static let glassRadius: CGFloat = 128
    /// Includes the wooden ring and the sill below it.
    static let windowTapSize = CGSize(width: 310, height: 310)

    /// The three letter blocks, each its own sprite so one can be lifted later.
    static let blockHeight: CGFloat = 92
    static let blockCentres: [CGPoint] = [
        CGPoint(x: 392, y: 282),
        CGPoint(x: 490, y: 286),
        CGPoint(x: 590, y: 282)
    ]
    static let blocksTapCentre = CGPoint(x: 490, y: 284)
    static let blocksTapSize   = CGSize(width: 310, height: 140)

    /// The rug, for reference — painted in, not tappable.
    static let rugCentre = CGPoint(x: 700, y: 176)
    static let rugSize   = CGSize(width: 850, height: 235)

    // MARK: The owl

    /// The owl's feet rest here; the rig is built upward from this point.
    static let owlHome = CGPoint(x: 703, y: 424)

    /// Drawn height of the owl sprite in design points.
    static let owlHeight: CGFloat = 372

    /// Where the owl lands when it goes to an object. Kept clear of the prop itself so
    /// the child can still see what they tapped.
    static func approachPoint(for object: RoomObjectID) -> CGPoint {
        switch object {
        case .owl:    return owlHome
        case .book:   return CGPoint(x: 392, y: 690)
        case .lamp:   return CGPoint(x: 330, y: 440)
        case .blocks: return CGPoint(x: 500, y: 200)
        case .window: return CGPoint(x: 1035, y: 470)
        }
    }

    // MARK: Depth

    enum Z {
        static let room: CGFloat        = -100
        static let windowSky: CGFloat   = -90
        static let windowWood: CGFloat  = -80
        static let props: CGFloat       = 10
        static let owl: CGFloat         = 20
        static let highlight: CGFloat   = 60
        static let ambientWash: CGFloat = 80
        static let debug: CGFloat       = 900
    }
}
