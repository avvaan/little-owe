import SpriteKit

/// What sits behind a mode while it runs.
///
/// It used to be a black sheet across the whole screen at two thirds opacity, and all
/// four modes had their own copy of it. It worked — cards and captions were legible
/// against it — but it read as **a dimmed screen rather than an owl in its house**. The
/// room is most of what this app is, and it disappeared the moment anything happened in
/// it.
///
/// So the room stays lit. A vignette darkens the corners, which does the same job of
/// pulling a child's eye to the middle, and a light wash takes just enough contrast out
/// of the background for white text to sit on it. The owl is still in its attic the whole
/// time.
final class ModeBackdrop: SKNode {

    /// How much light comes out of the room overall. Enough to separate the mode from the
    /// background, nowhere near enough to hide it.
    static let washAlpha: CGFloat = 0.28

    /// How dark the corners go. The vignette is what actually does the focusing.
    static let vignetteAlpha: CGFloat = 0.85

    private let wash = SKSpriteNode(color: SKColor(hex: 0x0A0714), size: RoomLayout.designSize)
    private let vignette: SKSpriteNode

    override init() {
        vignette = SKSpriteNode(texture: GradientTexture.vignette())
        // Wider than the room so the clear middle stays clear: a square gradient stretched
        // to a 4:3 screen would otherwise start darkening well before the corners.
        vignette.size = CGSize(width: RoomLayout.designSize.width * 1.25,
                               height: RoomLayout.designSize.height * 1.25)
        super.init()

        let centre = CGPoint(x: RoomLayout.designSize.width / 2,
                             y: RoomLayout.designSize.height / 2)
        wash.position = centre
        wash.alpha = 0
        vignette.position = centre
        vignette.alpha = 0

        zPosition = ModeLayer.backdrop
        addChild(wash)
        addChild(vignette)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Not supported") }

    /// Adds itself to `scene` if it is not already there, and fades in.
    func show(in scene: SKScene) {
        if parent == nil { scene.addChild(self) }
        removeAllActions()          // a pending fade-out from a quick exit and re-entry
        wash.removeAllActions()
        vignette.removeAllActions()
        alpha = 1
        wash.run(.fadeAlpha(to: ModeBackdrop.washAlpha, duration: 0.35))
        vignette.run(.fadeAlpha(to: ModeBackdrop.vignetteAlpha, duration: 0.35))
    }

    func hide() {
        run(.sequence([.fadeOut(withDuration: 0.3), .removeFromParent()]))
    }

    /// A soft dark panel to put behind words.
    ///
    /// With the room still lit, a caption can land on a pale patch of wall. This is the
    /// smallest thing that fixes it without bringing the black sheet back: it darkens
    /// only what is behind the text.
    static func scrim(size: CGSize, cornerRadius: CGFloat = 26) -> SKShapeNode {
        let panel = SKShapeNode(rectOf: size, cornerRadius: cornerRadius)
        panel.fillColor = SKColor(white: 0.02, alpha: 0.46)
        panel.strokeColor = .clear
        return panel
    }
}
