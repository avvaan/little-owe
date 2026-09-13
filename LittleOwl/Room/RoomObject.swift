import SpriteKit

/// The five things in the room a child can touch. Each maps to one mode; the modes
/// themselves arrive in later deliverables.
enum RoomObjectID: String, CaseIterable {
    case owl
    case book
    case lamp
    case blocks
    case window

    /// Mode names are for the code and the parent settings screen only. The child
    /// never sees a word of this.
    var modeDescription: String {
        switch self {
        case .owl:    return "Echo"
        case .book:   return "Stories"
        case .lamp:   return "Prayers and rhymes"
        case .blocks: return "Word games"
        case .window: return "Why questions"
        }
    }
}

/// A tappable prop.
///
/// Builders lay their artwork out around the node's own origin and hand over the
/// resulting local bounds; the scene then positions the whole thing. `hitArea` is kept
/// separate from the artwork and padded to at least `RoomLayout.minimumTapTarget` on
/// both axes, so small props (the lamp, a single block) are still comfortably reachable
/// by a three-year-old.
final class RoomObject: SKNode, Tappable {

    let id: RoomObjectID
    var tapID: RoomObjectID { id }

    /// In this node's own coordinate space.
    private(set) var localHitArea: CGRect

    private let content: SKNode

    /// Parent settings can hide any prop. Hidden props are not hit-tested.
    var isAvailable: Bool = true {
        didSet { isHidden = !isAvailable }
    }

    init(id: RoomObjectID, content: SKNode, localBounds: CGRect) {
        self.id = id
        self.content = content
        self.localHitArea = RoomObject.expand(localBounds, toAtLeast: RoomLayout.minimumTapTarget)
        super.init()
        name = id.rawValue
        addChild(content)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Not supported") }

    /// `point` is in the parent's coordinate space (the scene).
    func containsPoint(inParent point: CGPoint) -> Bool {
        guard isAvailable else { return false }
        let local = CGPoint(x: point.x - position.x, y: point.y - position.y)
        return localHitArea.contains(local)
    }

    /// The padded target, expressed in the parent's space — used for hit testing
    /// diagnostics and the debug overlay.
    var hitAreaInParent: CGRect {
        localHitArea.offsetBy(dx: position.x, dy: position.y)
    }

    /// Instant, unconditional feedback. It fires before any mode has had a chance to
    /// start, which is the whole point of the rule.
    func acknowledgeTap() {
        content.removeAction(forKey: "tapFeedback")
        content.setScale(1.0)
        content.run(
            .sequence([
                .scale(to: 1.08, duration: 0.07),
                .scale(to: 0.97, duration: 0.06),
                .scale(to: 1.00, duration: 0.09)
            ]),
            withKey: "tapFeedback"
        )
        SoundKit.shared.play(.tap)
    }

    private static func expand(_ rect: CGRect, toAtLeast minimum: CGFloat) -> CGRect {
        let width  = max(rect.width, minimum)
        let height = max(rect.height, minimum)
        return CGRect(
            x: rect.midX - width / 2,
            y: rect.midY - height / 2,
            width: width,
            height: height
        )
    }
}
