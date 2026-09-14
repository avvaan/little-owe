import SpriteKit
import UIKit

/// One page of a story: a picture, and the caption running underneath it.
///
/// Pages cross-fade rather than cut. A story is read at bedtime and a hard change every
/// fifteen seconds is the opposite of what that is for.
final class StoryPageNode: SKNode {

    private let panelSize: CGSize
    private let language: String

    private let panel = SKNode()
    private var artwork: SKNode?
    private let caption: CaptionNode

    /// Captions are optional and parent settings will drive this in deliverable 7.
    var showsCaptions = true {
        didSet { caption.isHidden = !showsCaptions }
    }

    init(panelSize: CGSize, captionWidth: CGFloat, language: String) {
        self.panelSize = panelSize
        self.language = language
        self.caption = CaptionNode(maxWidth: captionWidth)
        super.init()

        addChild(panel)
        caption.position = CGPoint(x: 0, y: -panelSize.height / 2 - 46)
        addChild(caption)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Not supported") }

    // MARK: Pages

    func show(page: Story.Page, hero: Hero, animated: Bool = true) {
        let incoming = makeArtwork(for: page, hero: hero)
        incoming.alpha = animated ? 0 : 1
        panel.addChild(incoming)

        let outgoing = artwork
        artwork = incoming

        if animated {
            incoming.run(.fadeIn(withDuration: 0.45))
            outgoing?.run(.sequence([.fadeOut(withDuration: 0.45), .removeFromParent()]))
        } else {
            outgoing?.removeFromParent()
        }

        caption.show(page.text)
        caption.alpha = animated ? 0 : 1
        if animated {
            caption.run(.fadeIn(withDuration: 0.3))
        }
    }

    func highlightCaption(range: NSRange) {
        guard showsCaptions else { return }
        caption.highlight(range: range)
    }

    func clear() {
        artwork?.removeFromParent()
        artwork = nil
        caption.clear()
    }

    // MARK: Artwork

    private func makeArtwork(for page: Story.Page, hero: Hero) -> SKNode {
        let node = SKNode()

        let frame = SKShapeNode(rectOf: panelSize, cornerRadius: 18)
        frame.fillColor = SKColor(white: 0.08, alpha: 0.55)
        frame.strokeColor = SKColor(white: 1, alpha: 0.22)
        frame.lineWidth = 3
        node.addChild(frame)

        if let name = page.illustration,
           let url = ContentLoader.illustrationURL(named: name, language: language),
           let image = UIImage(contentsOfFile: url.path) {
            let sprite = SKSpriteNode(texture: SKTexture(image: image))
            let scale = min(panelSize.width / sprite.size.width, panelSize.height / sprite.size.height)
            sprite.size = CGSize(width: sprite.size.width * scale, height: sprite.size.height * scale)
            node.addChild(sprite)
        } else {
            node.addChild(placeholder(for: hero))
        }
        return node
    }

    /// Until illustrations arrive, a page is a wash in the hero's colour with their
    /// silhouette in it. It is plainly a placeholder rather than a broken image, and it
    /// still tells a child whose story this is.
    private func placeholder(for hero: Hero) -> SKNode {
        let node = SKNode()
        let tint = SKColor(hex: hero.colour.flatMap { UInt32($0, radix: 16) } ?? 0xC9A06A)

        let wash = SKShapeNode(rectOf: CGSize(width: panelSize.width - 10,
                                              height: panelSize.height - 10), cornerRadius: 14)
        wash.fillColor = tint.withAlphaComponent(0.42)
        wash.strokeColor = .clear
        node.addChild(wash)

        let silhouette = SKShapeNode(path: HeroSilhouette.path(for: hero.id, height: panelSize.height * 0.52))
        silhouette.fillColor = SKColor(white: 0.12, alpha: 0.34)
        silhouette.strokeColor = .clear
        node.addChild(silhouette)

        return node
    }
}
