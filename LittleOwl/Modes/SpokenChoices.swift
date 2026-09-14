import SpriteKit
import UIKit

/// The no-recognition path: a row of cards the child taps, **named aloud by the owl**.
///
/// The brief asks Word games and Why to "fall back to a tap-to-choose picture answer" on
/// a device that cannot recognise speech. The pictures are not drawn yet, and the app
/// never asks a child to read — so the thing that makes these cards usable is not what is
/// on them. The owl says each option in turn while that card lights up, and the child
/// taps the one they remember hearing. A card is a place to aim, not a label.
///
/// Illustrations drop in later without touching this: a card shows
/// `choice_<something>.png` from the pack the moment one exists.
final class SpokenChoices {

    /// One option: what the owl says, and what it is called when a picture arrives.
    struct Option {
        let line: SpokenText
        let illustration: String?

        init(line: SpokenText, illustration: String? = nil) {
            self.line = line
            self.illustration = illustration
        }
    }

    private(set) var isPresenting = false

    /// Fires with the index of the option tapped.
    var onPick: ((Int) -> Void)?

    /// Fires once the owl has finished naming every card, so a mode can settle the owl
    /// back into waiting.
    var onNamed: (() -> Void)?

    private let scene: SKScene
    private let voice: OwlVoice
    private let language: String

    private var row: ChoiceRow?
    private var options: [Option] = []
    private var namingIndex = 0
    private var scheduled: [DispatchWorkItem] = []

    /// The mode's own `voice.onFinished`, put back the moment naming is over.
    ///
    /// `OwlVoice` is shared and has one completion, so naming the cards has to borrow it
    /// — and a borrowed callback that is never returned leaves the mode deaf to the end
    /// of every line it says afterwards.
    private var borrowedOnFinished: (() -> Void)?

    init(scene: SKScene, voice: OwlVoice, language: String) {
        self.scene = scene
        self.voice = voice
        self.language = language
    }

    // MARK: Presenting

    /// Puts the cards up and starts naming them. `centre` is in scene coordinates.
    ///
    /// Nothing times out: once the owl has named them all, the cards simply wait.
    func present(_ options: [Option], centre: CGPoint) {
        dismiss()
        guard !options.isEmpty else { return }

        self.options = options
        isPresenting = true

        let row = ChoiceRow(options: options, language: language)
        row.position = centre
        row.zPosition = ModeLayer.overlay
        scene.addChild(row)
        self.row = row

        borrowedOnFinished = voice.onFinished
        namingIndex = 0
        nameNext()
    }

    func dismiss() {
        cancelScheduled()
        returnTheVoice()
        row?.removeFromParent()
        row = nil
        options = []
        isPresenting = false
    }

    private func returnTheVoice() {
        guard let borrowedOnFinished else { return }
        voice.onFinished = borrowedOnFinished
        self.borrowedOnFinished = nil
    }

    /// `point` is in scene coordinates.
    func handleTap(at point: CGPoint) -> Bool {
        guard isPresenting, let row else { return false }
        guard let index = row.index(at: point) else { return false }

        // Naming stops the moment a child has made up their mind. Talking over a child
        // who has already answered is the opposite of listening.
        cancelScheduled()
        voice.stop()

        SoundKit.shared.play(.tap)
        row.acknowledgeTap(index)
        onPick?(index)
        return true
    }

    // MARK: Naming

    private func nameNext() {
        guard isPresenting, options.indices.contains(namingIndex) else {
            row?.highlight(nil)
            returnTheVoice()
            onNamed?()
            return
        }

        let index = namingIndex
        row?.highlight(index)
        voice.onFinished = { [weak self] in
            guard let self, self.isPresenting else { return }
            self.namingIndex += 1
            // A beat between options, so three names are three things rather than one
            // long sentence.
            self.after(0.35) { self.nameNext() }
        }
        voice.say(options[index].line)
    }

    private func after(_ delay: TimeInterval, _ block: @escaping () -> Void) {
        let item = DispatchWorkItem(block: block)
        scheduled.append(item)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func cancelScheduled() {
        scheduled.forEach { $0.cancel() }
        scheduled.removeAll()
    }
}

// MARK: - The cards

final class ChoiceRow: SKNode {

    /// Wider than the set cards because an option can be a whole question. Still well
    /// past the 88 pt floor on every supported screen.
    static let cardSize = CGSize(width: 300, height: 190)
    static let gap: CGFloat = 34

    private(set) var cards: [ChoiceCard] = []

    /// Three cards and their gaps: 968 points, inside the 1366-point canvas with room to
    /// spare after `.aspectFill` takes its crop.
    static func rowWidth(_ count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return CGFloat(count) * cardSize.width + CGFloat(count - 1) * gap
    }

    init(options: [SpokenChoices.Option], language: String) {
        super.init()

        var x = -ChoiceRow.rowWidth(options.count) / 2 + ChoiceRow.cardSize.width / 2
        for (index, option) in options.enumerated() {
            let card = ChoiceCard(option: option, size: ChoiceRow.cardSize,
                                  tint: ChoiceCard.tints[index % ChoiceCard.tints.count],
                                  language: language)
            card.position = CGPoint(x: x, y: 0)
            card.alpha = 0
            card.setScale(0.88)
            card.run(.sequence([
                .wait(forDuration: 0.06 * Double(index)),
                .group([.fadeIn(withDuration: 0.22), .scale(to: 1.0, duration: 0.26)])
            ]))
            addChild(card)
            cards.append(card)
            x += ChoiceRow.cardSize.width + ChoiceRow.gap
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Not supported") }

    /// `point` is in this node's parent's space.
    func index(at point: CGPoint) -> Int? {
        let local = CGPoint(x: (point.x - position.x) / (xScale == 0 ? 1 : xScale),
                            y: (point.y - position.y) / (yScale == 0 ? 1 : yScale))
        return cards.firstIndex { $0.contains(rowPoint: local) }
    }

    /// Lights the card the owl is naming, or none.
    func highlight(_ index: Int?) {
        for (position, card) in cards.enumerated() {
            card.setLit(position == index)
        }
    }

    func acknowledgeTap(_ index: Int) {
        guard cards.indices.contains(index) else { return }
        cards[index].acknowledgeTap()
    }
}

final class ChoiceCard: SKNode {

    /// Distinct enough to aim at and to remember for the few seconds between hearing a
    /// name and reaching for it. They carry no meaning: the owl's voice does that.
    static let tints: [UInt32] = [0x7FA8C9, 0xD9A05B, 0x8FB37A, 0xC48BA8, 0xB0A0D0]

    let hitArea: CGRect

    private let content = SKNode()
    private let card: SKShapeNode

    init(option: SpokenChoices.Option, size: CGSize, tint: UInt32, language: String) {
        self.hitArea = CGRect(x: -size.width / 2, y: -size.height / 2,
                              width: size.width, height: size.height)
        self.card = SKShapeNode(rectOf: size, cornerRadius: 22)
        super.init()
        addChild(content)

        card.fillColor = SKColor(hex: tint)
        card.strokeColor = SKColor(white: 1, alpha: 0.35)
        card.lineWidth = 4
        content.addChild(card)

        if let name = option.illustration,
           let url = ContentLoader.illustrationURL(named: name, language: language),
           let image = UIImage(contentsOfFile: url.path) {
            let sprite = SKSpriteNode(texture: SKTexture(image: image))
            let scale = min((size.width - 28) / sprite.size.width,
                            (size.height - 28) / sprite.size.height)
            sprite.size = CGSize(width: sprite.size.width * scale,
                                 height: sprite.size.height * scale)
            content.addChild(sprite)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Not supported") }

    func contains(rowPoint point: CGPoint) -> Bool {
        hitArea.contains(CGPoint(x: point.x - position.x, y: point.y - position.y))
    }

    /// Lit while the owl is saying this one. It is the only link between a card and its
    /// name, so it has to be unmissable rather than tasteful.
    func setLit(_ lit: Bool) {
        card.strokeColor = lit ? SKColor(hex: 0xFFE6B0) : SKColor(white: 1, alpha: 0.35)
        card.lineWidth = lit ? 7 : 4
        content.removeAction(forKey: "lit")
        content.run(.scale(to: lit ? 1.06 : 1.0, duration: 0.18), withKey: "lit")
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
