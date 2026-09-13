import SpriteKit

/// The round attic window.
///
/// The painted room has a night sky baked into its glass. To let the window follow the
/// device clock, that glass was split at export time into two sprites — the sky, and
/// the wooden muntins that cross it — so a different sky can be dropped in behind the
/// same woodwork. `tools/compose_room.py` does the splitting and can be re-run if the
/// painting is revised.
///
/// Laid out around its own origin: the glass is a circle of `radius` centred on (0, 0).
final class WindowNode: SKNode {

    private let radius: CGFloat
    private var sky: SKSpriteNode?

    private(set) var time: TimeOfDay

    init(radius: CGFloat, time: TimeOfDay) {
        self.radius = radius
        self.time = time
        super.init()
        buildWoodwork()
        setTime(time, animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Not supported") }

    /// Cross-fades to a new sky. Always animated in normal play — a hard cut at 17:00
    /// would read as a glitch.
    ///
    /// All four skies are painted. The fall back to night is kept for the case where a
    /// sky is ever removed from the bundle: the window is never empty.
    func setTime(_ newTime: TimeOfDay, animated: Bool = true) {
        time = newTime

        guard let texture = WindowNode.skyTexture(for: newTime) else { return }

        let incoming = SKSpriteNode(texture: texture)
        incoming.size = CGSize(width: radius * 2, height: radius * 2)
        incoming.zPosition = RoomLayout.Z.windowSky
        incoming.alpha = animated ? 0 : 1
        addChild(incoming)

        let outgoing = sky
        sky = incoming

        if animated {
            incoming.run(.fadeIn(withDuration: 1.4))
            outgoing?.run(.sequence([.fadeOut(withDuration: 1.4), .removeFromParent()]))
        } else {
            outgoing?.removeFromParent()
        }
    }

    /// Whether this time of day has its own painted sky yet.
    static func hasPaintedSky(for time: TimeOfDay) -> Bool {
        Bundle.main.url(forResource: "window_sky_\(time.rawValue)", withExtension: "png") != nil
    }

    private static func skyTexture(for time: TimeOfDay) -> SKTexture? {
        for name in ["window_sky_\(time.rawValue)", "window_sky_night"] {
            if Bundle.main.url(forResource: name, withExtension: "png") != nil {
                return SKTexture(imageNamed: name)
            }
        }
        assertionFailure("No window sky artwork in the bundle")
        return nil
    }

    private func buildWoodwork() {
        let wood = SKSpriteNode(imageNamed: "window_woodwork")
        wood.size = CGSize(width: radius * 2, height: radius * 2)
        wood.zPosition = RoomLayout.Z.windowWood
        addChild(wood)
    }
}
