import SpriteKit

/// Caption text that can light up one word at a time.
///
/// The brief asks for captions that run "word by word, for early readers", which rules
/// out a single `SKLabelNode` with `numberOfLines` — there is no way to address one word
/// inside it. So each word is its own label and this does the wrapping, which also makes
/// highlighting a matter of changing one node's colour.
///
/// Captions are the only text a child ever sees, and they are optional: parent settings
/// turn them off in deliverable 7.
final class CaptionNode: SKNode {

    private struct Word {
        /// Where this word sits in the original string, so a spoken range can find it.
        let range: NSRange
        let label: SKLabelNode
    }

    private let maxWidth: CGFloat
    private let fontSize: CGFloat
    private let fontName: String

    private var words: [Word] = []

    /// Which word is lit, if any. Exposed so tests can assert on it without comparing
    /// colours across colour spaces, which is a losing game.
    private(set) var highlightedIndex: Int?

    /// The display words, in order — "Hello," is one, not two.
    var wordTexts: [String] { words.map { $0.label.text ?? "" } }

    /// Soft enough to sit under a picture without competing with it.
    var restingColour = SKColor(white: 0.94, alpha: 0.72)
    /// The word being said.
    var spokenColour = SKColor(hex: 0xFFE6B0)

    init(maxWidth: CGFloat, fontSize: CGFloat = 40, fontName: String = "AvenirNext-Medium") {
        self.maxWidth = maxWidth
        self.fontSize = fontSize
        self.fontName = fontName
        super.init()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Not supported") }

    /// How tall the laid-out caption is. The caller positions this node by its top.
    private(set) var height: CGFloat = 0

    // MARK: Content

    func show(_ text: String) {
        clear()

        let ns = text as NSString
        var pending: [Word] = []

        // Display tokens keep their punctuation — "sleep," is one word to a reader, even
        // though word enumeration would hand back just "sleep".
        var cursor = 0
        while cursor < ns.length {
            let remaining = NSRange(location: cursor, length: ns.length - cursor)
            let space = ns.rangeOfCharacter(from: .whitespacesAndNewlines, options: [], range: remaining)
            let end = space.location == NSNotFound ? ns.length : space.location
            if end > cursor {
                let range = NSRange(location: cursor, length: end - cursor)
                pending.append(Word(range: range, label: makeLabel(ns.substring(with: range))))
            }
            cursor = space.location == NSNotFound ? ns.length : space.location + space.length
        }

        layout(pending)
        words = pending
        pending.forEach { addChild($0.label) }
    }

    func clear() {
        words.forEach { $0.label.removeFromParent() }
        words.removeAll()
        highlightedIndex = nil
        height = 0
    }

    /// Lights the word covering `range`. A range that falls between words — punctuation,
    /// a space — leaves the previous one lit rather than going dark mid-sentence.
    func highlight(range: NSRange) {
        guard let index = words.firstIndex(where: { NSIntersectionRange($0.range, range).length > 0 })
        else { return }
        highlight(index: index)
    }

    func highlightAll() {
        highlightedIndex = nil
        for word in words {
            word.label.fontColor = spokenColour
            word.label.setScale(1)
        }
    }

    private func highlight(index: Int) {
        guard index != highlightedIndex, words.indices.contains(index) else { return }

        if let previous = highlightedIndex, words.indices.contains(previous) {
            words[previous].label.removeAllActions()
            words[previous].label.fontColor = restingColour
            words[previous].label.setScale(1)
        }

        highlightedIndex = index
        let label = words[index].label
        label.fontColor = spokenColour
        label.removeAllActions()
        // A breath of scale, not a jump: the eye should be drawn, not startled.
        label.run(.sequence([
            .scale(to: 1.06, duration: 0.07),
            .scale(to: 1.0, duration: 0.14)
        ]))
    }

    // MARK: Layout

    private func makeLabel(_ text: String) -> SKLabelNode {
        let label = SKLabelNode(fontNamed: fontName)
        label.text = text
        label.fontSize = fontSize
        label.fontColor = restingColour
        label.horizontalAlignmentMode = .left
        label.verticalAlignmentMode = .top
        return label
    }

    /// Greedy wrapping, then each line centred. Positions are relative to this node's
    /// origin, which sits at the top centre of the caption.
    private func layout(_ words: [Word]) {
        let spaceWidth = fontSize * 0.28
        let lineHeight = fontSize * 1.34

        var lines: [[Word]] = [[]]
        var lineWidth: CGFloat = 0

        for word in words {
            let width = word.label.frame.width
            let needed = lines[lines.count - 1].isEmpty ? width : lineWidth + spaceWidth + width
            if needed > maxWidth, !lines[lines.count - 1].isEmpty {
                lines.append([word])
                lineWidth = width
            } else {
                lines[lines.count - 1].append(word)
                lineWidth = needed
            }
        }

        for (index, line) in lines.enumerated() where !line.isEmpty {
            let total = line.reduce(CGFloat(0)) { $0 + $1.label.frame.width }
                + spaceWidth * CGFloat(line.count - 1)
            var x = -total / 2
            let y = -CGFloat(index) * lineHeight
            for word in line {
                word.label.position = CGPoint(x: x, y: y)
                x += word.label.frame.width + spaceWidth
            }
        }

        height = CGFloat(lines.filter { !$0.isEmpty }.count) * lineHeight
    }
}
