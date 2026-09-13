import SpriteKit

/// Stories: the child picks a hero, the owl reads them a story, the pages turn
/// themselves.
///
/// The turn is: tap the book → the room dims, the owl flies up to the shelf → five
/// cards → tap one → the owl reads, a page at a time, captions lighting up word by word
/// → at the end the owl asks "again?" and the book glows.
///
/// Tapping the owl leaves, at any point. Nothing else times out: a child who wanders
/// off mid-story comes back to the same page, waiting.
final class StoryMode {

    enum Phase {
        case idle
        case choosingHero
        case reading
        /// The story is over and the book is offering another.
        case finished
    }

    private(set) var phase: Phase = .idle
    var isRunning: Bool { phase != .idle }

    /// True while tapping the book means "again" rather than "start".
    var canReplay: Bool { phase == .finished }

    /// Fires when the child has left the story and the room is theirs again.
    var onLeave: (() -> Void)?

    /// True while the story is over and the book is the way to hear it again. The scene
    /// lifts the book above the dimming and lets it glow while this holds — the brief
    /// asks for "tap the book", and a book the child cannot see is not an offer.
    var onOfferAgain: ((Bool) -> Void)?

    // MARK: Tuning

    /// A beat between the last word of a page and the first of the next, so a page is a
    /// breath rather than a conveyor.
    var pageTurnPause: TimeInterval = 0.55

    /// Where the owl stands to read: left of the page, clear of both the picture and
    /// the caption, and far enough from the edge to survive `.aspectFill` cropping the
    /// sides on a narrow iPad.
    var readingSpot = CGPoint(x: 150, y: 372)
    var readingScale: CGFloat = 0.6

    // MARK: Collaborators

    private let scene: SKScene
    private let owl: OwlNode
    private let pack: ContentPack
    private let voice: OwlVoice

    private let dim = SKSpriteNode(color: SKColor(white: 0.03, alpha: 1), size: RoomLayout.designSize)
    private var picker: HeroPicker?
    private var pageNode: StoryPageNode?

    private var story: Story?
    private var pageIndex = 0
    private var lastStoryID: String?
    private var scheduled: [DispatchWorkItem] = []

    // MARK: Init

    init(scene: SKScene, owl: OwlNode, pack: ContentPack, voice: OwlVoice) {
        self.scene = scene
        self.owl = owl
        self.pack = pack
        self.voice = voice

        dim.position = CGPoint(x: RoomLayout.designSize.width / 2,
                               y: RoomLayout.designSize.height / 2)
        dim.zPosition = Z.dim
        dim.alpha = 0
    }

    // MARK: Starting and stopping

    func begin() {
        guard phase == .idle else { return }
        guard !pack.heroes.isEmpty else {
            // A pack with no heroes is a broken pack, not a state to design around.
            assertionFailure("Stories opened with no heroes in the pack")
            return
        }

        if dim.parent == nil { scene.addChild(dim) }
        dim.run(.fadeAlpha(to: 0.62, duration: 0.35))

        // The owl is lit while it reads: it sits above the dimming, not behind it. It
        // stays on its perch for now, so the cards get the full width of the room.
        owl.zPosition = Z.owl
        owl.transition(to: .listening)

        showPicker()
    }

    /// Tear everything down and give the room back.
    func leave() {
        guard phase != .idle else { return }
        cancelScheduled()

        voice.stop()
        owl.setMouthOpenness(0)

        picker?.removeFromParent()
        picker = nil
        pageNode?.run(.sequence([.fadeOut(withDuration: 0.25), .removeFromParent()]))
        pageNode = nil

        story = nil
        pageIndex = 0
        phase = .idle
        onOfferAgain?(false)

        // Leave nothing of this mode hanging off the shared voice.
        voice.onWordRange = nil
        voice.onMouth = nil
        voice.onFinished = nil

        dim.run(.sequence([.fadeOut(withDuration: 0.3), .removeFromParent()]))
        owl.run(.scale(to: 1.0, duration: 0.4))
        owl.zPosition = RoomLayout.Z.owl
        owl.transition(to: .idle)
        owl.returnHome()

        onLeave?()
    }

    // MARK: Input

    /// Taps on the hero cards. Everything else in the room is behind the dimming and is
    /// handled by the scene.
    func handleTap(at point: CGPoint) -> Bool {
        guard phase == .choosingHero else { return false }
        return picker?.handleTap(at: point) ?? false
    }

    /// The book was tapped while a story was on screen.
    func bookTapped() {
        switch phase {
        case .finished:
            guard let story else { return }
            read(story)
        case .choosingHero, .reading, .idle:
            break
        }
    }

    // MARK: Choosing

    private func showPicker() {
        phase = .choosingHero

        let picker = HeroPicker(heroes: pack.heroes, language: pack.language)
        picker.position = CGPoint(x: RoomLayout.designSize.width / 2, y: 470)
        picker.zPosition = Z.overlay
        picker.onPick = { [weak self] hero in self?.pick(hero) }
        scene.addChild(picker)
        self.picker = picker
    }

    private func pick(_ hero: Hero) {
        let stories = pack.stories(for: hero.id)
        guard !stories.isEmpty else {
            assertionFailure("hero \(hero.id) has no stories; a content test should have caught this")
            return
        }

        // Avoid repeating the story just heard, unless that hero has only one.
        let fresh = stories.filter { $0.id != lastStoryID }
        let chosen = (fresh.isEmpty ? stories : fresh).randomElement()!

        picker?.dismiss()
        picker = nil

        // Now the owl moves aside, to the left of where the page will appear.
        owl.travel(to: readingSpot)
        owl.run(.scale(to: readingScale, duration: 0.5))

        read(chosen)
    }

    // MARK: Reading

    private func read(_ story: Story) {
        cancelScheduled()
        onOfferAgain?(false)
        self.story = story
        lastStoryID = story.id
        pageIndex = 0
        phase = .reading

        if pageNode == nil {
            let node = StoryPageNode(panelSize: Z.panelSize, captionWidth: Z.captionWidth,
                                     language: pack.language)
            node.position = CGPoint(x: Z.panelCentre.x, y: Z.panelCentre.y)
            node.zPosition = Z.overlay
            node.alpha = 0
            scene.addChild(node)
            node.run(.fadeIn(withDuration: 0.3))
            pageNode = node
        }

        voice.onWordRange = { [weak self] range in
            self?.pageNode?.highlightCaption(range: range)
        }
        voice.onMouth = { [weak self] openness in
            self?.owl.setMouthOpenness(openness)
        }
        voice.onFinished = { [weak self] in
            self?.pageFinished()
        }

        showCurrentPage(animated: false)
    }

    private func showCurrentPage(animated: Bool) {
        guard let story, let hero = pack.hero(story.heroID),
              story.pages.indices.contains(pageIndex) else { return }

        let page = story.pages[pageIndex]
        pageNode?.show(page: page, hero: hero, animated: animated)

        owl.transition(to: .speaking)
        voice.say(page)
    }

    private func pageFinished() {
        guard phase == .reading, let story else { return }

        guard pageIndex + 1 < story.pages.count else {
            finishStory()
            return
        }

        after(pageTurnPause) { [weak self] in
            guard let self, self.phase == .reading else { return }
            self.pageIndex += 1
            self.showCurrentPage(animated: true)
        }
    }

    private func finishStory() {
        phase = .finished
        owl.transition(to: .happy)
        onOfferAgain?(true)

        // "Again?" — the owl asks, and the book is what answers. The scene lifts the
        // book above the dimming while this phase lasts.
        guard let again = pack.phrase(.storyAgain) else {
            owl.transition(to: .idle)
            return
        }

        voice.onFinished = { [weak self] in
            self?.owl.transition(to: .idle)
        }
        after(0.5) { [weak self] in
            guard let self, self.phase == .finished else { return }
            self.owl.transition(to: .speaking)
            self.voice.say(again)
        }
    }

    // MARK: Scheduling

    private func after(_ delay: TimeInterval, _ block: @escaping () -> Void) {
        let item = DispatchWorkItem(block: block)
        scheduled.append(item)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func cancelScheduled() {
        scheduled.forEach { $0.cancel() }
        scheduled.removeAll()
    }

    private enum Z {
        static let dim: CGFloat = 200
        static let owl: CGFloat = 210
        static let overlay: CGFloat = 220

        /// Right of the owl, which reads from the left.
        static let panelCentre = CGPoint(x: 800, y: 620)
        static let panelSize = CGSize(width: 880, height: 400)
        static let captionWidth: CGFloat = 900
    }
}
