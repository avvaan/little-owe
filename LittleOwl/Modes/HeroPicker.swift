import SpriteKit
import UIKit

/// The row of cards a child taps to choose whose story they want.
///
/// No text, no names: a three-year-old picks the bunny because it is the bunny. Until
/// the artist delivers `hero_<id>.png` the cards carry a flat silhouette in the hero's
/// colour, which is enough to tell a fox from a bear at a glance — a coloured rectangle
/// would not be.
final class HeroPicker: SKNode {

    /// Comfortably past the 88 pt floor at every supported screen size. Five of these
    /// plus the gaps come to 1012 points, which fits the 1366-point canvas with room to
    /// spare on the narrowest iPad once `.aspectFill` has taken its crop.
    static let cardSize = CGSize(width: 180, height: 230)
    private static let gap: CGFloat = 28

    private(set) var cards: [HeroCard] = []
    var onPick: ((Hero) -> Void)?

    init(heroes: [Hero], language: String) {
        super.init()

        let total = CGFloat(heroes.count) * Self.cardSize.width
            + CGFloat(max(heroes.count - 1, 0)) * Self.gap
        var x = -total / 2 + Self.cardSize.width / 2

        for (index, hero) in heroes.enumerated() {
            let card = HeroCard(hero: hero, size: Self.cardSize, language: language)
            card.position = CGPoint(x: x, y: 0)
            // A short stagger so the row arrives as a row, not as a wall.
            card.alpha = 0
            card.setScale(0.86)
            card.run(.sequence([
                .wait(forDuration: 0.05 * Double(index)),
                .group([
                    .fadeIn(withDuration: 0.22),
                    .scale(to: 1.0, duration: 0.26)
                ])
            ]))
            addChild(card)
            cards.append(card)
            x += Self.cardSize.width + Self.gap
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Not supported") }

    /// `point` is in the parent's coordinate space.
    func handleTap(at point: CGPoint) -> Bool {
        let local = CGPoint(x: point.x - position.x, y: point.y - position.y)
        guard let card = cards.first(where: { $0.hitArea.contains(local) }) else { return false }

        SoundKit.shared.play(.tap)
        card.acknowledgeTap()
        onPick?(card.hero)
        return true
    }

    func dismiss() {
        for (index, card) in cards.enumerated() {
            card.run(.sequence([
                .wait(forDuration: 0.03 * Double(index)),
                .group([.fadeOut(withDuration: 0.18), .scale(to: 0.9, duration: 0.18)])
            ]))
        }
        run(.sequence([.wait(forDuration: 0.45), .removeFromParent()]))
    }
}

// MARK: - One card

final class HeroCard: SKNode {

    let hero: Hero
    let hitArea: CGRect

    private let content = SKNode()

    init(hero: Hero, size: CGSize, language: String) {
        self.hero = hero
        self.hitArea = CGRect(x: -size.width / 2, y: -size.height / 2,
                              width: size.width, height: size.height)
        super.init()
        addChild(content)

        // `colour` is six hex digits in the content file; the fallback is the room's wood.
        let tint = SKColor(hex: hero.colour.flatMap { UInt32($0, radix: 16) } ?? 0xC9A06A)

        let card = SKShapeNode(rectOf: size, cornerRadius: 22)
        card.fillColor = tint
        card.strokeColor = SKColor(white: 1, alpha: 0.5)
        card.lineWidth = 4
        content.addChild(card)

        if let url = ContentLoader.illustrationURL(named: hero.card ?? "", language: language),
           let image = UIImage(contentsOfFile: url.path) {
            let sprite = SKSpriteNode(texture: SKTexture(image: image))
            let scale = min((size.width - 24) / sprite.size.width,
                            (size.height - 24) / sprite.size.height)
            sprite.size = CGSize(width: sprite.size.width * scale, height: sprite.size.height * scale)
            content.addChild(sprite)
        } else {
            let silhouette = SKShapeNode(path: HeroSilhouette.path(for: hero.id, height: size.height * 0.62))
            silhouette.fillColor = SKColor(white: 0.15, alpha: 0.62)
            silhouette.strokeColor = .clear
            silhouette.position = CGPoint(x: 0, y: -size.height * 0.06)
            content.addChild(silhouette)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Not supported") }

    func acknowledgeTap() {
        content.removeAllActions()
        content.setScale(1)
        content.run(.sequence([
            .scale(to: 1.10, duration: 0.08),
            .scale(to: 1.00, duration: 0.12)
        ]))
    }
}

// MARK: - Placeholder silhouettes

/// Flat animal heads, enough to tell the cards apart until real illustrations land.
/// Each is drawn around its own centre, `height` tall.
enum HeroSilhouette {

    static func path(for heroID: String, height: CGFloat) -> CGPath {
        switch heroID {
        case "fox":      return fox(height)
        case "bunny":    return bunny(height)
        case "bear":     return bear(height)
        case "mouse":    return mouse(height)
        case "hedgehog": return hedgehog(height)
        default:         return bear(height)
        }
    }

    private static func head(_ path: CGMutablePath, width: CGFloat, height: CGFloat, y: CGFloat) {
        path.addEllipse(in: CGRect(x: -width / 2, y: y - height / 2, width: width, height: height))
    }

    private static func fox(_ h: CGFloat) -> CGPath {
        let path = CGMutablePath()
        // Pointed snout and tall triangular ears.
        path.move(to: CGPoint(x: -h * 0.42, y: h * 0.10))
        path.addLine(to: CGPoint(x: -h * 0.30, y: h * 0.46))
        path.addLine(to: CGPoint(x: -h * 0.10, y: h * 0.18))
        path.addLine(to: CGPoint(x: h * 0.10, y: h * 0.18))
        path.addLine(to: CGPoint(x: h * 0.30, y: h * 0.46))
        path.addLine(to: CGPoint(x: h * 0.42, y: h * 0.10))
        path.addLine(to: CGPoint(x: 0, y: -h * 0.50))
        path.closeSubpath()
        return path
    }

    private static func bunny(_ h: CGFloat) -> CGPath {
        let path = CGMutablePath()
        head(path, width: h * 0.72, height: h * 0.66, y: -h * 0.12)
        for side in [CGFloat(-1), CGFloat(1)] {
            path.addEllipse(in: CGRect(x: side * h * 0.24 - h * 0.09, y: h * 0.12,
                                       width: h * 0.18, height: h * 0.46))
        }
        return path
    }

    private static func bear(_ h: CGFloat) -> CGPath {
        let path = CGMutablePath()
        head(path, width: h * 0.84, height: h * 0.76, y: -h * 0.06)
        for side in [CGFloat(-1), CGFloat(1)] {
            path.addEllipse(in: CGRect(x: side * h * 0.34 - h * 0.13, y: h * 0.22,
                                       width: h * 0.26, height: h * 0.26))
        }
        return path
    }

    private static func mouse(_ h: CGFloat) -> CGPath {
        let path = CGMutablePath()
        head(path, width: h * 0.66, height: h * 0.62, y: -h * 0.14)
        for side in [CGFloat(-1), CGFloat(1)] {
            path.addEllipse(in: CGRect(x: side * h * 0.32 - h * 0.20, y: h * 0.06,
                                       width: h * 0.40, height: h * 0.40))
        }
        return path
    }

    private static func hedgehog(_ h: CGFloat) -> CGPath {
        let path = CGMutablePath()
        head(path, width: h * 0.80, height: h * 0.64, y: -h * 0.14)
        // A crown of spines.
        var angle = CGFloat.pi * 0.08
        while angle <= CGFloat.pi * 0.92 {
            let base = CGPoint(x: cos(angle) * h * 0.38, y: sin(angle) * h * 0.30 - h * 0.10)
            let tip = CGPoint(x: cos(angle) * h * 0.56, y: sin(angle) * h * 0.50 - h * 0.10)
            path.move(to: CGPoint(x: base.x - h * 0.05, y: base.y))
            path.addLine(to: tip)
            path.addLine(to: CGPoint(x: base.x + h * 0.05, y: base.y))
            path.closeSubpath()
            angle += CGFloat.pi * 0.105
        }
        return path
    }
}
