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
/// Some props are their own sprites (the blocks, the window) and can be squashed when
/// touched. Others — the book on the shelf, the lamp on the table — are painted into
/// the room and cannot move at all, so they answer a tap with a soft glow instead.
/// Both satisfy the rule that every tap gets instant sound *and* motion.
///
/// `hitArea` is kept separate from the artwork and padded to at least
/// `RoomLayout.minimumTapTarget` on both axes, so small props are still comfortably
/// reachable by a three-year-old.
final class RoomObject: SKNode, Tappable {

    enum Feedback {
        /// The prop is a sprite: squash it.
        case squash
        /// The prop is painted into the room: bloom a soft light over it.
        case glow(size: CGSize)
    }

    let id: RoomObjectID
    var tapID: RoomObjectID { id }

    /// In this node's own coordinate space.
    private(set) var localHitArea: CGRect

    private let content: SKNode?
    private let feedback: Feedback
    private var glowNode: SKSpriteNode?

    /// Parent settings can hide any prop. Hidden props are not hit-tested.
    var isAvailable: Bool = true {
        didSet {
            isHidden = !isAvailable
        }
    }

    init(id: RoomObjectID, content: SKNode?, localBounds: CGRect, feedback: Feedback) {
        self.id = id
        self.content = content
        self.feedback = feedback
        self.localHitArea = RoomObject.expand(localBounds, toAtLeast: RoomLayout.minimumTapTarget)
        super.init()
        name = id.rawValue
        if let content { addChild(content) }
        if case .glow(let size) = feedback { addChild(makeGlow(size: size)) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Not supported") }

    /// `point` is in the parent's coordinate space (the scene).
    func containsPoint(inParent point: CGPoint) -> Bool {
        guard isAvailable else { return false }
        let local = CGPoint(x: point.x - position.x, y: point.y - position.y)
        return localHitArea.contains(local)
    }

    /// The padded target, expressed in the parent's space — used by the debug overlay.
    var hitAreaInParent: CGRect {
        localHitArea.offsetBy(dx: position.x, dy: position.y)
    }

    /// Instant, unconditional feedback. It fires before any mode has had a chance to
    /// start, which is the whole point of the rule.
    func acknowledgeTap() {
        SoundKit.shared.play(.tap)

        switch feedback {
        case .squash:
            guard let content else { return }
            content.removeAction(forKey: Key.feedback)
            content.setScale(1.0)
            content.run(
                .sequence([
                    .scale(to: 1.09, duration: 0.07),
                    .scale(to: 0.97, duration: 0.06),
                    .scale(to: 1.00, duration: 0.09)
                ]),
                withKey: Key.feedback
            )

        case .glow:
            guard let glowNode else { return }
            glowNode.removeAction(forKey: Key.feedback)
            glowNode.alpha = 0
            glowNode.setScale(0.86)
            glowNode.run(
                .group([
                    .sequence([
                        .fadeAlpha(to: 0.55, duration: 0.09),
                        .fadeAlpha(to: 0.0, duration: 0.34)
                    ]),
                    .scale(to: 1.06, duration: 0.43)
                ]),
                withKey: Key.feedback
            )
        }
    }

    /// A slow breathing glow over a prop the mode above is offering — "tap this to hear
    /// it again".
    ///
    /// It has to be the glow that breathes, not the node. The book and the lamp are
    /// painted into the room and have no artwork of their own, so a prop node at rest is
    /// a hit area and a glow held at alpha 0: fading *that* between 0.72 and 1 changes
    /// nothing a child can see.
    func setOffering(_ offering: Bool) {
        guard let glowNode else { return }
        glowNode.removeAction(forKey: Key.offering)

        guard offering else {
            // A tap on the offered prop turns the offer off, so the tap's own glow may
            // be mid-flight. It ends at zero by itself; stomping it would swallow the
            // feedback for the very tap that got us here.
            if glowNode.action(forKey: Key.feedback) == nil {
                glowNode.setScale(1)
                glowNode.run(.fadeAlpha(to: 0, duration: 0.3))
            }
            return
        }

        glowNode.setScale(1)
        glowNode.alpha = 0
        glowNode.run(.repeatForever(.sequence([
            .group([.fadeAlpha(to: 0.5, duration: 0.9), .scale(to: 1.04, duration: 0.9)]),
            .group([.fadeAlpha(to: 0.18, duration: 0.9), .scale(to: 1.0, duration: 0.9)])
        ])), withKey: Key.offering)
    }

    private func makeGlow(size: CGSize) -> SKSpriteNode {
        let glow = SKSpriteNode(texture: GradientTexture.radialGlow(Palette.tapGlow))
        glow.size = size
        glow.blendMode = .add
        glow.alpha = 0
        glow.zPosition = RoomLayout.Z.highlight
        glowNode = glow
        return glow
    }

    private enum Key {
        static let feedback = "prop.feedback"
        static let offering = "prop.offering"
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
