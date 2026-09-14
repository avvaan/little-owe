import SpriteKit

/// Word games: the owl sets a little task and the child answers out loud.
///
/// Tap the blocks → the room dims, the owl hops down to them → "Can you name an animal
/// that starts with M?" → the child says something → the owl is delighted, or says what
/// it was thinking of, and asks the next one. Tapping the owl leaves.
///
/// **No scores, no streaks, nothing kept.** The mode never counts anything, in memory or
/// anywhere else, because a three-year-old who gets one wrong should not then be a
/// three-year-old with a number attached. The brief asks for this and the code has no
/// place to put a score even if someone wanted one.
///
/// There is no "wrong" branch either. An answer that is not on the list gets a warm line
/// and the answer the owl had in mind — "Good try! I think it's a monkey!" — and then the
/// next task, which is exactly what a kind grown-up does.
final class WordGameMode: RoomMode {

    enum Phase {
        case idle
        /// The owl is asking, praising or revealing.
        case talking
        /// The child's turn, out loud.
        case listening
        /// The child's turn, by tapping, on a device that cannot hear.
        case choosing
    }

    private(set) var phase: Phase = .idle
    var isRunning: Bool { phase != .idle }

    var onLeave: (() -> Void)?

    /// Captions are the only text a child ever sees, and a parent can turn them off.
    var captionsEnabled = true {
        didSet { caption.isHidden = !captionsEnabled }
    }

    /// The blocks are never an "again" offer: the game simply goes on until the child
    /// taps the owl. Nothing here ends by itself.
    var againProp: RoomObjectID? { nil }

    // MARK: Tuning

    var beatBeforeAnswering: TimeInterval = 0.4
    var beatBetweenTasks: TimeInterval = 0.7

    /// Where the owl settles: down on the rug at the left, where the blocks are, and
    /// clear of the band the answer cards need.
    var playingSpot = CGPoint(x: 200, y: 250)

    /// The cards sit to the owl's right, low, where nothing else is.
    var choicesCentre = CGPoint(x: 830, y: 330)

    // MARK: Collaborators

    private let scene: SKScene
    private let owl: OwlNode
    private let pack: ContentPack
    private let voice: OwlVoice
    private let turn: ListeningTurn
    private let choices: SpokenChoices

    private let backdrop = ModeBackdrop()
    private let caption = CaptionNode(maxWidth: 940, fontSize: 48)
    private let halo: SKShapeNode

    // MARK: Turn state

    private var game: WordGame?
    /// The last few asked, so the same task does not come round twice in a minute. It is
    /// not a score and it is not kept: it dies with the visit.
    private var recentlyAsked: [String] = []

    private enum Utterance { case prompt, praise, kindTry, reveal, chooseInvite }
    private var utterance: Utterance = .prompt

    /// Which card was the right one, once the row has been shuffled.
    private var correctChoice = 0

    private var scheduled: [DispatchWorkItem] = []

    // MARK: Init

    init(scene: SKScene, owl: OwlNode, pack: ContentPack, voice: OwlVoice) {
        self.scene = scene
        self.owl = owl
        self.pack = pack
        self.voice = voice
        self.turn = ListeningTurn(recognitionLocale: pack.recognitionLocale)
        self.choices = SpokenChoices(scene: scene, voice: voice, language: pack.language)

        halo = ListeningHalo.make()

        caption.position = CGPoint(x: 830, y: 870)
        caption.zPosition = ModeLayer.overlay

        choices.onPick = { [weak self] index in self?.cardTapped(index) }
        // The owl is talking while it reads the cards, and waiting once it stops.
        choices.onNamed = { [weak self] in self?.owl.transition(to: .listening) }
    }

    var canBegin: Bool { !pack.wordGames.isEmpty }

    // MARK: Starting and stopping

    func begin() {
        guard phase == .idle, canBegin else { return }
        turn.prepare()

        backdrop.show(in: scene)

        owl.zPosition = ModeLayer.owl
        if halo.parent == nil { owl.addChild(halo) }
        if caption.parent == nil { scene.addChild(caption) }

        voice.onWordRange = { [weak self] range in self?.caption.highlight(range: range) }
        voice.onMouth = { [weak self] openness in self?.owl.setMouthOpenness(openness) }
        voice.onFinished = { [weak self] in self?.owlFinishedSpeaking() }

        owl.travel(to: playingSpot)
        askNext()
    }

    func leave() {
        guard phase != .idle else { return }
        cancelScheduled()

        voice.stop()
        owl.setMouthOpenness(0)
        turn.cancel()
        choices.dismiss()

        caption.clear()
        caption.removeFromParent()
        ListeningHalo.hide(halo)
        halo.removeFromParent()

        game = nil
        recentlyAsked.removeAll()
        phase = .idle

        voice.onWordRange = nil
        voice.onMouth = nil
        voice.onFinished = nil

        backdrop.hide()
        owl.zPosition = RoomLayout.Z.owl
        owl.transition(to: .idle)
        owl.returnHome()

        onLeave?()
    }

    // MARK: Input

    func handleTap(at point: CGPoint) -> Bool {
        guard phase == .choosing else { return false }
        return choices.handleTap(at: point)
    }

    func againTapped() {}

    // MARK: Asking

    private func askNext() {
        guard let next = pickGame() else { return }
        game = next
        remember(next.id)

        phase = .talking
        caption.show(next.prompt)
        caption.alpha = 0
        caption.run(.fadeIn(withDuration: 0.25))
        speak(next.promptLine, as: .prompt)
    }

    /// Avoids the handful just asked, unless the bank is smaller than that.
    private func pickGame() -> WordGame? {
        let fresh = pack.wordGames.filter { !recentlyAsked.contains($0.id) }
        return (fresh.isEmpty ? pack.wordGames : fresh).randomElement()
    }

    private func remember(_ id: String) {
        recentlyAsked.append(id)
        let window = max(1, min(6, pack.wordGames.count - 1))
        if recentlyAsked.count > window { recentlyAsked.removeFirst() }
    }

    private func speak(_ line: any Speakable, as utterance: Utterance) {
        self.utterance = utterance
        owl.transition(to: .speaking)
        voice.say(line)
    }

    private func owlFinishedSpeaking() {
        guard isRunning else { return }

        switch utterance {
        case .prompt:
            // On a device that can hear, the child answers out loud. On one that cannot,
            // the cards come up and the owl reads them.
            if turn.canHear {
                after(beatBeforeAnswering) { [weak self] in self?.openChildTurn() }
            } else if let invite = pack.phrase(.chooseInvite) {
                speak(invite, as: .chooseInvite)
            } else {
                showChoices()
            }

        case .chooseInvite:
            showChoices()

        case .praise, .reveal:
            after(beatBetweenTasks) { [weak self] in self?.askNext() }

        case .kindTry:
            // The kind line and the answer are two halves of one thought, so they follow
            // one another without a gap to fall into.
            guard let game else { return }
            speak(game.revealLine, as: .reveal)
        }
    }

    // MARK: Answering out loud

    private func openChildTurn() {
        guard phase == .talking, game != nil else { return }
        phase = .listening
        owl.transition(to: .listening)
        ListeningHalo.show(halo)

        turn.begin(fallbackPause: 4) { [weak self] outcome in
            self?.closeChildTurn(outcome)
        }
    }

    private func closeChildTurn(_ outcome: ListeningTurn.Outcome) {
        guard phase == .listening, let game else { return }
        ListeningHalo.hide(halo)

        switch outcome {
        case .heard(let heard) where AnswerMatcher.accepts(heard: heard, anyOf: game.accepted):
            praise()

        case .heard, .nothing:
            kindly()

        case .waited:
            // The microphone went away mid-visit. Fall back to the cards rather than
            // pretending to have heard something.
            showChoices()
        }
    }

    // MARK: Answering by tapping

    private func showChoices() {
        guard let game, !game.choices.isEmpty else {
            after(beatBetweenTasks) { [weak self] in self?.askNext() }
            return
        }
        phase = .choosing
        owl.transition(to: .speaking)

        // The correct answer is first in the content file, so it is easy to check there.
        // It must not be first on screen.
        let order = game.choices.indices.shuffled()
        correctChoice = order.firstIndex(of: game.choices.startIndex) ?? 0

        let options = order.map { index -> SpokenChoices.Option in
            let word = game.choices[index]
            return SpokenChoices.Option(
                line: SpokenText(id: "\(game.id)-\(index)", text: word,
                                 stem: "game_\(game.id)_choice_\(index)"),
                illustration: "choice_\(word).png"
            )
        }
        choices.present(options, centre: choicesCentre)
    }

    private func cardTapped(_ index: Int) {
        guard phase == .choosing else { return }
        choices.dismiss()
        if index == correctChoice { praise() } else { kindly() }
    }

    // MARK: Endings

    private func praise() {
        phase = .talking
        owl.transition(to: .happy)
        guard let praise = pack.phrase(.praise) else {
            after(beatBetweenTasks) { [weak self] in self?.askNext() }
            return
        }
        speak(praise, as: .praise)
    }

    /// What the owl says when the answer was not on the list. It never says wrong, never
    /// corrects, and always moves on.
    private func kindly() {
        phase = .talking
        guard let kind = pack.phrase(.kindTry) else {
            guard let game else { return }
            speak(game.revealLine, as: .reveal)
            return
        }
        speak(kind, as: .kindTry)
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
}

// MARK: - The listening ring

/// The ring that appears round the owl while it is the child's turn.
///
/// A child who cannot read needs to be told whose turn it is without a word, and the
/// owl's own posture is not quite enough on its own. Shared by every mode that listens,
/// so the cue means the same thing everywhere in the app.
enum ListeningHalo {

    static func make() -> SKShapeNode {
        let ring = SKShapeNode(circleOfRadius: RoomLayout.owlHeight * 0.60)
        ring.strokeColor = SKColor(hex: 0xFFE6B0).withAlphaComponent(0.6)
        ring.fillColor = .clear
        ring.lineWidth = 7
        ring.position = CGPoint(x: 0, y: RoomLayout.owlHeight * 0.5)
        ring.zPosition = -1
        ring.alpha = 0
        return ring
    }

    static func show(_ ring: SKShapeNode) {
        ring.removeAllActions()
        ring.setScale(1)
        ring.run(.fadeAlpha(to: 0.75, duration: 0.2))
        ring.run(.repeatForever(.sequence([
            .group([.scale(to: 1.06, duration: 0.9), .fadeAlpha(to: 0.45, duration: 0.9)]),
            .group([.scale(to: 1.00, duration: 0.9), .fadeAlpha(to: 0.75, duration: 0.9)])
        ])), withKey: "pulse")
    }

    static func hide(_ ring: SKShapeNode) {
        ring.removeAction(forKey: "pulse")
        ring.run(.fadeOut(withDuration: 0.25))
    }
}
