import SpriteKit

/// The round attic window. Everything behind the glass is generated, so the sky can
/// change with the device clock without shipping four illustrations.
///
/// Laid out around its own origin: the glass is a circle of `radius` centred on (0, 0).
final class WindowNode: SKNode {

    private let radius: CGFloat
    private let glass = SKCropNode()
    private let skyContainer = SKNode()
    private var currentSky: SKNode?

    private(set) var time: TimeOfDay

    init(radius: CGFloat, time: TimeOfDay) {
        self.radius = radius
        self.time = time
        super.init()

        buildGlass()
        buildFrame()
        setTime(time, animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Not supported") }

    // MARK: Public

    /// Cross-fades to a new sky. Always animated in normal play — a hard cut at 17:00
    /// would read as a glitch.
    func setTime(_ newTime: TimeOfDay, animated: Bool = true) {
        time = newTime
        let sky = WindowNode.makeSky(for: newTime, radius: radius)
        sky.alpha = animated ? 0 : 1
        skyContainer.addChild(sky)

        let outgoing = currentSky
        currentSky = sky

        if animated {
            sky.run(.fadeIn(withDuration: 1.4))
            outgoing?.run(.sequence([.fadeOut(withDuration: 1.4), .removeFromParent()]))
        } else {
            outgoing?.removeFromParent()
        }
    }

    /// Colour and strength of the light this window throws into the room.
    static func spill(for time: TimeOfDay) -> (color: SKColor, alpha: CGFloat) {
        switch time {
        case .morning: return (SKColor(hex: 0xFFD79A), 0.20)
        case .day:     return (SKColor(hex: 0xEAF4FF), 0.14)
        case .evening: return (SKColor(hex: 0xE2A070), 0.12)
        case .night:   return (SKColor(hex: 0x9FB6E8), 0.07)
        }
    }

    // MARK: Build

    private func buildGlass() {
        // A sprite mask rather than an SKShapeNode: shape nodes are unreliable as crop
        // masks on some GPUs, and this costs one small texture.
        let mask = SKSpriteNode(texture: GradientTexture.solidCircle(diameter: radius * 2))
        mask.size = CGSize(width: radius * 2, height: radius * 2)
        glass.maskNode = mask
        glass.zPosition = RoomLayout.Z.windowGlass
        glass.addChild(skyContainer)
        addChild(glass)
    }

    private func buildFrame() {
        let frame = SKNode()
        frame.zPosition = RoomLayout.Z.windowFrame

        let ring = SKShapeNode(circleOfRadius: radius)
        ring.fillColor = .clear
        ring.strokeColor = Palette.wood
        ring.lineWidth = 26
        frame.addChild(ring)

        let innerRing = SKShapeNode(circleOfRadius: radius - 10)
        innerRing.fillColor = .clear
        innerRing.strokeColor = Palette.woodDark
        innerRing.lineWidth = 4
        innerRing.alpha = 0.6
        frame.addChild(innerRing)

        // Two muntins. They read as "window" instantly and break up the glass.
        for isVertical in [true, false] {
            let bar = SKShapeNode(rectOf: isVertical
                ? CGSize(width: 12, height: radius * 2 - 14)
                : CGSize(width: radius * 2 - 14, height: 12))
            bar.fillColor = Palette.woodLight
            bar.strokeColor = .clear
            frame.addChild(bar)
        }

        // Sill.
        let sill = SKShapeNode(rectOf: CGSize(width: radius * 2.3, height: 22), cornerRadius: 6)
        sill.fillColor = Palette.wood
        sill.strokeColor = Palette.woodDark
        sill.lineWidth = 2
        sill.position = CGPoint(x: 0, y: -radius - 6)
        frame.addChild(sill)

        addChild(frame)
    }

    // MARK: Skies

    private static func makeSky(for time: TimeOfDay, radius: CGFloat) -> SKNode {
        let node = SKNode()
        let diameter = radius * 2

        let colors: [SKColor]
        switch time {
        case .morning: colors = Palette.skyMorning
        case .day:     colors = Palette.skyDay
        case .evening: colors = Palette.skyEvening
        case .night:   colors = Palette.skyNight
        }

        let backdrop = SKSpriteNode(texture: GradientTexture.vertical(colors))
        backdrop.size = CGSize(width: diameter + 4, height: diameter + 4)
        node.addChild(backdrop)

        switch time {
        case .morning:
            node.addChild(sun(radius: radius))
            node.addChild(cloud(width: 132, at: CGPoint(x: -radius * 0.1, y: radius * 0.42), drift: 58, radius: radius, alpha: 0.75))
        case .day:
            node.addChild(cloud(width: 160, at: CGPoint(x: -radius * 0.3, y: radius * 0.46), drift: 46, radius: radius, alpha: 0.95))
            node.addChild(cloud(width: 112, at: CGPoint(x: radius * 0.35, y: radius * 0.08), drift: 64, radius: radius, alpha: 0.85))
            node.addChild(cloud(width: 190, at: CGPoint(x: 0, y: -radius * 0.36), drift: 88, radius: radius, alpha: 0.7))
        case .evening:
            node.addChild(moon(radius: radius, at: CGPoint(x: radius * 0.34, y: radius * 0.16), scale: 0.9))
            node.addChild(starfield(radius: radius, count: 7, maxAlpha: 0.45))
            node.addChild(cloud(width: 150, at: CGPoint(x: -radius * 0.2, y: -radius * 0.3), drift: 96, radius: radius, alpha: 0.35))
        case .night:
            node.addChild(moon(radius: radius, at: CGPoint(x: radius * 0.26, y: radius * 0.42), scale: 1.0))
            node.addChild(starfield(radius: radius, count: 16, maxAlpha: 0.95))
        }

        return node
    }

    private static func sun(radius: CGFloat) -> SKNode {
        let glow = SKSpriteNode(texture: GradientTexture.radialGlow(Palette.sun))
        glow.size = CGSize(width: radius * 1.9, height: radius * 1.9)
        glow.position = CGPoint(x: -radius * 0.34, y: -radius * 0.18)
        glow.blendMode = .add
        glow.alpha = 0.85

        let disc = SKShapeNode(circleOfRadius: radius * 0.24)
        disc.fillColor = Palette.sun
        disc.strokeColor = .clear
        disc.position = glow.position

        // A very slow breath keeps the morning sky from looking like a still image.
        glow.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.62, duration: 5.0),
            .fadeAlpha(to: 0.85, duration: 5.0)
        ])))

        let node = SKNode()
        node.addChild(glow)
        node.addChild(disc)
        return node
    }

    private static func moon(radius: CGFloat, at point: CGPoint, scale: CGFloat) -> SKNode {
        let node = SKNode()
        let discRadius = radius * 0.2 * scale

        let halo = SKSpriteNode(texture: GradientTexture.radialGlow(Palette.moon))
        halo.size = CGSize(width: discRadius * 6, height: discRadius * 6)
        halo.blendMode = .add
        halo.alpha = 0.32
        node.addChild(halo)

        let disc = SKShapeNode(circleOfRadius: discRadius)
        disc.fillColor = Palette.moon
        disc.strokeColor = .clear
        node.addChild(disc)

        // Craters, so the moon is a face a child can look at rather than a dot.
        let craters: [(CGFloat, CGFloat, CGFloat)] = [(-0.3, 0.22, 0.24), (0.28, 0.3, 0.17), (0.1, -0.34, 0.2)]
        for (dx, dy, size) in craters {
            let crater = SKShapeNode(circleOfRadius: discRadius * size)
            crater.fillColor = SKColor(white: 0.82, alpha: 0.45)
            crater.strokeColor = .clear
            crater.position = CGPoint(x: discRadius * dx, y: discRadius * dy)
            node.addChild(crater)
        }

        node.position = point
        return node
    }

    private static func cloud(width: CGFloat, at point: CGPoint, drift: TimeInterval, radius: CGFloat, alpha: CGFloat) -> SKNode {
        let cloud = SKNode()
        let puffs: [(CGFloat, CGFloat, CGFloat)] = [
            (-0.34, -0.02, 0.26), (-0.08, 0.10, 0.34), (0.18, 0.01, 0.28), (0.38, -0.06, 0.20)
        ]
        for (dx, dy, size) in puffs {
            let puff = SKShapeNode(circleOfRadius: width * size)
            puff.fillColor = Palette.cloud
            puff.strokeColor = .clear
            puff.position = CGPoint(x: width * dx, y: width * dy)
            cloud.addChild(puff)
        }
        cloud.alpha = alpha

        // Drifts left to right and wraps; the crop node hides the reset. `point.x` only
        // sets the starting phase so the clouds do not travel in lockstep.
        let startX = -radius - width * 0.7
        let endX   =  radius + width * 0.7
        let span   = endX - startX
        let phase  = min(max((point.x - startX) / span, 0), 0.95)

        cloud.position = CGPoint(x: startX + span * phase, y: point.y)
        cloud.run(.sequence([
            .moveTo(x: endX, duration: drift * TimeInterval(1 - phase)),
            .repeatForever(.sequence([
                .moveTo(x: startX, duration: 0),
                .moveTo(x: endX, duration: drift)
            ]))
        ]))
        return cloud
    }

    private static func starfield(radius: CGFloat, count: Int, maxAlpha: CGFloat) -> SKNode {
        let field = SKNode()
        // Deterministic placement: the same sky every night is reassuring, and it keeps
        // this build reproducible for screenshots.
        var seed: UInt64 = 0x5EED
        func next() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat((seed >> 33) % 10_000) / 10_000
        }

        for index in 0..<count {
            let angle = next() * .pi * 2
            let distance = (0.25 + next() * 0.66) * radius
            let star = SKShapeNode(circleOfRadius: 2 + next() * 2.6)
            star.fillColor = Palette.star
            star.strokeColor = .clear
            star.position = CGPoint(x: cos(angle) * distance, y: sin(angle) * distance)
            star.alpha = maxAlpha * (0.4 + next() * 0.6)

            let period = 1.6 + Double(index % 5) * 0.7
            star.run(.repeatForever(.sequence([
                .fadeAlpha(to: star.alpha * 0.25, duration: period),
                .fadeAlpha(to: star.alpha, duration: period)
            ])))
            field.addChild(star)
        }
        return field
    }
}
