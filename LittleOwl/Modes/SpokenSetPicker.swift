import SpriteKit
import UIKit

/// The cards a child taps to choose which prayer or rhyme they want.
///
/// Same rule as the hero cards: no words. A three-year-old cannot read "Before meals",
/// but they know the bowl, the moon and the star, and after two evenings they reach for
/// the same card without looking. That is also why the order comes from the pack rather
/// than from whatever the parent happened to tick last.
///
/// The row wraps, because a parent may leave anything from one set to ten on the lamp.
final class SpokenSetPicker: SKNode {

    /// Well past the 88 pt floor at every supported screen size, and sized so the whole
    /// shipped pack — seven sets — fits one row across the canvas with room to spare
    /// after `.aspectFill` takes its crop. One row matters: the band of room below the
    /// owl's feet is the only place a row of cards does not land on the owl.
    static let cardSize = CGSize(width: 148, height: 186)
    static let gap: CGFloat = 20
    static let rowGap: CGFloat = 22
    static let maxPerRow = 7

    private(set) var cards: [SpokenSetCard] = []
    var onPick: ((SpokenSet) -> Void)?

    /// How the cards split across rows: as even as possible, never more than
    /// `maxPerRow` in one. Seven sets come out as four and three, not five and two.
    static func rows(for count: Int) -> [Int] {
        guard count > 0 else { return [] }
        let rowCount = Int((Double(count) / Double(maxPerRow)).rounded(.up))
        let base = count / rowCount
        let extra = count % rowCount
        return (0..<rowCount).map { base + ($0 < extra ? 1 : 0) }
    }

    /// How wide a row of `count` cards is, for the test that keeps the picker on screen.
    static func rowWidth(_ count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return CGFloat(count) * cardSize.width + CGFloat(count - 1) * gap
    }

    /// How tall the laid-out cards are, before any scaling. The mode uses it to keep the
    /// picker in the clear band below the owl however many sets a parent has left on.
    private(set) var contentHeight: CGFloat = 0

    init(sets: [SpokenSet], language: String = "en") {
        super.init()

        let layout = SpokenSetPicker.rows(for: sets.count)
        let totalHeight = CGFloat(layout.count) * SpokenSetPicker.cardSize.height
            + CGFloat(max(layout.count - 1, 0)) * SpokenSetPicker.rowGap
        contentHeight = totalHeight

        var index = 0
        var y = totalHeight / 2 - SpokenSetPicker.cardSize.height / 2

        for rowCount in layout {
            var x = -SpokenSetPicker.rowWidth(rowCount) / 2 + SpokenSetPicker.cardSize.width / 2
            for _ in 0..<rowCount {
                let card = SpokenSetCard(set: sets[index], size: SpokenSetPicker.cardSize,
                                         language: language)
                card.position = CGPoint(x: x, y: y)
                // A short stagger, so the cards arrive as a group rather than a wall.
                card.alpha = 0
                card.setScale(0.86)
                card.run(.sequence([
                    .wait(forDuration: 0.05 * Double(index)),
                    .group([.fadeIn(withDuration: 0.22), .scale(to: 1.0, duration: 0.26)])
                ]))
                addChild(card)
                cards.append(card)
                x += SpokenSetPicker.cardSize.width + SpokenSetPicker.gap
                index += 1
            }
            y -= SpokenSetPicker.cardSize.height + SpokenSetPicker.rowGap
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Not supported") }

    /// `point` is in the parent's coordinate space. The node may have been scaled down
    /// to fit, so the scale comes off as well as the position — otherwise the cards drift
    /// further from their hit areas the smaller the picker gets.
    func handleTap(at point: CGPoint) -> Bool {
        guard xScale != 0, yScale != 0 else { return false }
        let local = CGPoint(x: (point.x - position.x) / xScale,
                            y: (point.y - position.y) / yScale)
        guard let card = cards.first(where: { $0.contains(rowPoint: local) }) else { return false }

        SoundKit.shared.play(.tap)
        card.acknowledgeTap()
        onPick?(card.set)
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

final class SpokenSetCard: SKNode {

    let set: SpokenSet
    /// In this card's own space.
    let hitArea: CGRect

    private let content = SKNode()

    init(set: SpokenSet, size: CGSize, language: String = "en") {
        self.set = set
        self.hitArea = CGRect(x: -size.width / 2, y: -size.height / 2,
                              width: size.width, height: size.height)
        super.init()
        addChild(content)

        let card = SKShapeNode(rectOf: size, cornerRadius: 22)
        card.fillColor = SKColor(hex: set.colour.flatMap { UInt32($0, radix: 16) } ?? 0xC9A06A)
        card.strokeColor = SKColor(white: 1, alpha: 0.5)
        card.lineWidth = 4
        content.addChild(card)

        if let picture = Self.picture(for: set, size: size, language: language) {
            content.addChild(picture)
        } else {
            // Until the painting for this set arrives. A flat white shape is plainly a
            // placeholder rather than a broken picture, and it still tells a child which
            // card is which once the owl has named them.
            let symbol = SKShapeNode(path: SetSymbol.path(for: set.symbol, height: size.height * 0.52))
            symbol.fillColor = SKColor(white: 1, alpha: 0.86)
            symbol.strokeColor = .clear
            content.addChild(symbol)
        }
    }

    /// The painting for this set, cropped to fill the card and rounded to its corners.
    ///
    /// Filled rather than fitted: a painting letterboxed inside a coloured rectangle
    /// looks like a mistake, and these are cards a three-year-old picks between at a
    /// glance. The crop is centred, which is why the pictures are painted with their
    /// subject in the middle.
    private static func picture(for set: SpokenSet, size: CGSize, language: String) -> SKNode? {
        guard let url = ContentLoader.illustrationURL(named: set.illustration, language: language),
              let image = UIImage(contentsOfFile: url.path) else { return nil }

        let texture = SKTexture(image: image)
        let sprite = SKSpriteNode(texture: texture)

        let scale = max(size.width / texture.size().width, size.height / texture.size().height)
        sprite.size = CGSize(width: texture.size().width * scale,
                             height: texture.size().height * scale)

        // Rounded to the card's own corners, so the painting cannot poke out of them.
        let mask = SKShapeNode(rectOf: size, cornerRadius: 22)
        mask.fillColor = .white
        mask.strokeColor = .clear

        let crop = SKCropNode()
        crop.maskNode = mask
        crop.addChild(sprite)
        return crop
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Not supported") }

    /// `point` is in the picker's space; `hitArea` is in the card's own.
    func contains(rowPoint point: CGPoint) -> Bool {
        hitArea.contains(CGPoint(x: point.x - position.x, y: point.y - position.y))
    }

    func acknowledgeTap() {
        content.removeAllActions()
        content.setScale(1)
        content.run(.sequence([
            .scale(to: 1.10, duration: 0.08),
            .scale(to: 1.00, duration: 0.12)
        ]))
    }
}

// MARK: - The symbols

/// Flat shapes, one per set, drawn around their own centre and `height` tall.
///
/// They are not decoration: they are the entire label. Each one has to be recognisable
/// at a glance and, more importantly, unmistakable for any other one on the same screen —
/// which is why the evening prayer is a moon and the bedtime rhyme is a star rather than
/// both being something round in the sky.
enum SetSymbol: String, CaseIterable {
    case sun, moon, bowl, star, egg, note, boat

    /// Unknown names fall back rather than crash — a content file is data, and data can
    /// be wrong without taking the app down in front of a child.
    static func path(for name: String, height: CGFloat) -> CGPath {
        (SetSymbol(rawValue: name) ?? .star).path(height: height)
    }

    func path(height h: CGFloat) -> CGPath {
        switch self {
        case .sun:  return SetSymbol.sun(h)
        case .moon: return SetSymbol.moon(h)
        case .bowl: return SetSymbol.bowl(h)
        case .star: return SetSymbol.star(h)
        case .egg:  return SetSymbol.egg(h)
        case .note: return SetSymbol.note(h)
        case .boat: return SetSymbol.boat(h)
        }
    }

    private static func sun(_ h: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let core = h * 0.27
        path.addEllipse(in: CGRect(x: -core, y: -core, width: core * 2, height: core * 2))

        var angle: CGFloat = 0
        let step = CGFloat.pi / 4
        while angle < .pi * 2 - 0.001 {
            let inner = core * 1.18
            let outer = h * 0.5
            let spread = step * 0.16
            path.move(to: CGPoint(x: cos(angle - spread) * inner, y: sin(angle - spread) * inner))
            path.addLine(to: CGPoint(x: cos(angle) * outer, y: sin(angle) * outer))
            path.addLine(to: CGPoint(x: cos(angle + spread) * inner, y: sin(angle + spread) * inner))
            path.closeSubpath()
            angle += step
        }
        return path
    }

    private static func moon(_ h: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let r = h * 0.5
        // Outer disc one way, a smaller offset disc the other: opposite winding leaves
        // the bite out of it.
        path.addArc(center: .zero, radius: r, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        path.move(to: CGPoint(x: r * 0.40 + r * 0.86, y: 0))
        path.addArc(center: CGPoint(x: r * 0.40, y: 0), radius: r * 0.86,
                    startAngle: 0, endAngle: .pi * 2, clockwise: true)
        return path
    }

    private static func bowl(_ h: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let w = h * 0.46
        // A half-round bowl with a rim, and steam curling off it.
        path.move(to: CGPoint(x: -w, y: -h * 0.02))
        path.addQuadCurve(to: CGPoint(x: w, y: -h * 0.02),
                          control: CGPoint(x: 0, y: -h * 0.72))
        path.closeSubpath()
        path.addRect(CGRect(x: -w * 1.12, y: -h * 0.06, width: w * 2.24, height: h * 0.09))

        // One curl of steam, centred. Two marks above a rimmed half-disc read as a face
        // rather than as dinner, which is the kind of thing you only see once it is
        // drawn.
        let stroke = h * 0.05
        path.move(to: CGPoint(x: -stroke / 2, y: h * 0.10))
        path.addCurve(to: CGPoint(x: -stroke / 2, y: h * 0.40),
                      control1: CGPoint(x: h * 0.14, y: h * 0.18),
                      control2: CGPoint(x: -h * 0.14, y: h * 0.30))
        path.addLine(to: CGPoint(x: stroke / 2, y: h * 0.40))
        path.addCurve(to: CGPoint(x: stroke / 2, y: h * 0.10),
                      control1: CGPoint(x: -h * 0.14 + stroke, y: h * 0.30),
                      control2: CGPoint(x: h * 0.14 + stroke, y: h * 0.18))
        path.closeSubpath()
        return path
    }

    private static func star(_ h: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let outer = h * 0.5
        let inner = outer * 0.42
        for index in 0..<10 {
            let angle = -CGFloat.pi / 2 + CGFloat(index) * .pi / 5
            let radius = index.isMultiple(of: 2) ? outer : inner
            let point = CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    private static func egg(_ h: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let w = h * 0.36
        // Narrower at the top than the bottom, which is what makes it an egg and not a
        // moon: two curves meeting at the tip.
        path.move(to: CGPoint(x: 0, y: h * 0.5))
        path.addCurve(to: CGPoint(x: 0, y: -h * 0.5),
                      control1: CGPoint(x: w * 1.35, y: h * 0.06),
                      control2: CGPoint(x: w * 1.12, y: -h * 0.5))
        path.addCurve(to: CGPoint(x: 0, y: h * 0.5),
                      control1: CGPoint(x: -w * 1.12, y: -h * 0.5),
                      control2: CGPoint(x: -w * 1.35, y: h * 0.06))
        path.closeSubpath()
        return path
    }

    private static func note(_ h: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let head = h * 0.16
        path.addEllipse(in: CGRect(x: -h * 0.30, y: -h * 0.5,
                                   width: head * 2.2, height: head * 1.7))
        path.addRect(CGRect(x: -h * 0.30 + head * 1.85, y: -h * 0.42,
                            width: h * 0.055, height: h * 0.9))
        path.move(to: CGPoint(x: -h * 0.30 + head * 1.85, y: h * 0.48))
        path.addQuadCurve(to: CGPoint(x: h * 0.30, y: h * 0.06),
                          control: CGPoint(x: h * 0.34, y: h * 0.42))
        path.addQuadCurve(to: CGPoint(x: -h * 0.30 + head * 1.85, y: h * 0.30),
                          control: CGPoint(x: h * 0.10, y: h * 0.24))
        path.closeSubpath()
        return path
    }

    private static func boat(_ h: CGFloat) -> CGPath {
        let path = CGMutablePath()
        // Hull.
        path.move(to: CGPoint(x: -h * 0.48, y: -h * 0.16))
        path.addLine(to: CGPoint(x: h * 0.48, y: -h * 0.16))
        path.addLine(to: CGPoint(x: h * 0.30, y: -h * 0.40))
        path.addLine(to: CGPoint(x: -h * 0.30, y: -h * 0.40))
        path.closeSubpath()
        // Mast and sail.
        path.addRect(CGRect(x: -h * 0.025, y: -h * 0.16, width: h * 0.05, height: h * 0.70))
        path.move(to: CGPoint(x: h * 0.04, y: h * 0.50))
        path.addLine(to: CGPoint(x: h * 0.40, y: -h * 0.08))
        path.addLine(to: CGPoint(x: h * 0.04, y: -h * 0.08))
        path.closeSubpath()
        return path
    }
}
