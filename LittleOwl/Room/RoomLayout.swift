import SpriteKit

/// Fixed design canvas. The scene is authored at this size and drawn with
/// `.aspectFill`, so on every supported iPad the room fills the screen and only a
/// little is cropped from the long edge.
enum RoomLayout {

    static let designSize = CGSize(width: 1366, height: 1024)

    // MARK: Tap targets

    /// The UX rule is 88 x 88 **points on the device**. With `.aspectFill` the scene is
    /// scaled down on every iPad narrower than 4:3; the worst case in the supported
    /// range is the 10th-gen iPad at 1180 x 820 pt, where
    ///   scale = max(1180/1366, 820/1024) = 0.864
    /// so 88 pt on screen needs 88 / 0.864 = 102 design points. We round well past that.
    /// `DebugOverlay` draws these rectangles so the margin can be checked on device.
    static let minimumTapTarget: CGFloat = 120

    // MARK: Room shell

    static let floorLine: CGFloat = 300
    static let eaveHeight: CGFloat = 745
    static let ridgeHeight: CGFloat = 1024
    static var ridgeX: CGFloat { designSize.width / 2 }

    /// Back wall: floor line, up both sides to the eaves, then two slopes to the ridge.
    static var wallPath: CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: floorLine))
        path.addLine(to: CGPoint(x: 0, y: eaveHeight))
        path.addLine(to: CGPoint(x: ridgeX, y: ridgeHeight))
        path.addLine(to: CGPoint(x: designSize.width, y: eaveHeight))
        path.addLine(to: CGPoint(x: designSize.width, y: floorLine))
        path.closeSubpath()
        return path
    }

    // MARK: Props

    static let shelfRect   = CGRect(x: 80,  y: 706, width: 360, height: 26)
    static let bookAnchor  = CGPoint(x: 258, y: 792)

    static let tableTopRect = CGRect(x: 92,  y: 442, width: 232, height: 24)
    static let lampAnchor   = CGPoint(x: 208, y: 466)

    static let windowCentre = CGPoint(x: 1012, y: 716)
    static let windowRadius: CGFloat = 138

    static let rugCentre = CGPoint(x: 700, y: 186)
    static let rugSize   = CGSize(width: 780, height: 236)
    static let blocksAnchor = CGPoint(x: 498, y: 208)

    static let perchCentre = CGPoint(x: 716, y: 346)
    /// The owl's feet rest here; everything in the rig is built upward from the origin.
    static let owlHome     = CGPoint(x: 716, y: 392)

    /// Where the owl lands when it goes to an object. Kept clear of the prop itself so
    /// the child can still see what they tapped.
    static func approachPoint(for object: RoomObjectID) -> CGPoint {
        switch object {
        case .owl:    return owlHome
        case .book:   return CGPoint(x: 360, y: 758)
        case .lamp:   return CGPoint(x: 330, y: 470)
        case .blocks: return CGPoint(x: 470, y: 268)
        case .window: return CGPoint(x: 1012, y: 470)
        }
    }

    // MARK: Depth

    enum Z {
        static let sky: CGFloat        = -100
        /// Roof planes, gable wall, beams and floor are one baked sprite.
        static let wall: CGFloat       = -90
        static let windowGlass: CGFloat = -70
        static let windowFrame: CGFloat = -60
        static let floor: CGFloat      = -40
        static let rug: CGFloat        = -30
        static let furniture: CGFloat  = -10
        /// In front of the floor and the furniture: light falls *on* the room, and at
        /// -50 it was drawing behind the floorboards it is supposed to land on.
        static let lightSpill: CGFloat = 6
        static let props: CGFloat      = 10
        static let perch: CGFloat      = 18
        static let owl: CGFloat        = 20
        static let ambientWash: CGFloat = 80
        static let debug: CGFloat      = 900
    }
}
