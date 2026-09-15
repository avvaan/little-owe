import SpriteKit

/// The way a child changes who lives in the attic: a small round portrait of the other
/// animal, up in the corner. Tap it and the two swap places.
///
/// It is a picture of an animal, not a button, which is the whole rule this app is
/// built on — there is no word on it and nothing to read. A child who taps it sees the
/// animal in the corner become the animal on the perch, which explains itself the first
/// time and needs no explaining again.
///
/// **Where it sits, and why exactly there.** The room is authored at 1366 × 1024 and
/// drawn with `.aspectFill`, which on the narrowest iPad crops 63 points off the top.
/// The window's tap target already occupies x 880–1190 up to y 879. So this sits to the
/// right of the window and below the crop, with its whole target inside the picture on
/// every iPad this ships to.
final class CharacterPicker: SKNode, Tappable {

    /// Measured against the crop, not chosen by eye. See the note above.
    static let centre = CGPoint(x: 1265, y: 890)
    static let diameter: CGFloat = 132

    /// The character this badge offers — the one that is *not* on the perch.
    private(set) var offered: Character

    var onPick: ((Character) -> Void)?

    private let portrait = SKSpriteNode()
    private let disc: SKShapeNode

    init(offering character: Character) {
        offered = character

        disc = SKShapeNode(circleOfRadius: Self.diameter / 2)
        disc.fillColor = SKColor(hex: 0x2A1E14).withAlphaComponent(0.55)
        disc.strokeColor = SKColor(hex: 0xC9A06A).withAlphaComponent(0.70)
        disc.lineWidth = 3

        super.init()

        position = Self.centre
        zPosition = RoomLayout.Z.props
        addChild(disc)

        // The painting is portrait and tall; fit it inside the disc by height and let
        // it sit a little low, the way a face fits a locket.
        portrait.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        portrait.position = CGPoint(x: 0, y: -Self.diameter * 0.02)
        addChild(portrait)

        show(character)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Not supported") }

    // MARK: Contents

    func show(_ character: Character) {
        offered = character
        guard let texture = ArtTexture.texture(named: "\(character.artPrefix)_base") else {
            // Nothing to offer. The scene only builds a picker when there is a second
            // character, so this is a broken bundle rather than a state to design for.
            isHidden = true
            return
        }
        isHidden = false
        portrait.texture = texture

        let height = Self.diameter * 0.82
        let aspect = texture.size().width / texture.size().height
        portrait.size = CGSize(width: height * aspect, height: height)
    }

    /// Swaps the badge to show whoever is now not on the perch.
    func nowOnThePerch(_ character: Character) {
        let others = Character.available.filter { $0 != character }
        guard let next = others.first else {
            isHidden = true
            return
        }
        show(next)
        run(.sequence([
            .scale(to: 0.82, duration: 0.10),
            .scale(to: 1.06, duration: 0.12),
            .scale(to: 1.00, duration: 0.10)
        ]))
    }

    // MARK: Tappable

    var tapID: RoomObjectID { .owl }

    /// Generously past the 88 pt floor: the disc is 132 design points and the target is
    /// squarer and larger again, because a corner is harder to hit than a middle.
    var localHitArea: CGRect {
        CGRect(x: -RoomLayout.minimumTapTarget / 2, y: -RoomLayout.minimumTapTarget / 2,
               width: RoomLayout.minimumTapTarget, height: RoomLayout.minimumTapTarget)
    }

    var hitAreaInParent: CGRect { localHitArea.offsetBy(dx: position.x, dy: position.y) }

    func containsPoint(inParent point: CGPoint) -> Bool {
        !isHidden && localHitArea.contains(CGPoint(x: point.x - position.x,
                                                   y: point.y - position.y))
    }

    func acknowledgeTap() {
        SoundKit.shared.play(.tap, volumeScale: 0.9)
        onPick?(offered)
    }
}
