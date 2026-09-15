import SpriteKit

/// The basket in the corner: the owl does the asking.
///
/// Tap the basket → the owl goes over to it → "I have been wondering about something."
/// → three painted cards come up, and the owl says what each one is about while that
/// card lights → the child taps whichever they want to hear → the owl answers it, and
/// lays out three more. Tapping the owl leaves.
///
/// This is the other half of the window. At the window the child asks and the owl
/// answers; here the owl offers and the child chooses. Same bank of questions, same
/// written answers, opposite direction — and it is the half that works with no
/// microphone at all, because nothing here needs to hear anything.
///
/// **The owl never invents an answer here either.** Every card is a `Question` from the
/// pack and every answer is the sentence written next to it. The only thing this file
/// decides is which three to lay out.
///
/// The cards carry the real paintings — `question_<id>` — rather than the coloured
/// rectangles they started as. That matters more here than anywhere else in the app: at
/// the window the cards are a fallback a child may never see, and here they *are* the
/// mode. A child who cannot read has to be able to tell three questions apart by
/// looking at them, and then remember which one the owl named.
final class WonderMode: RoomMode {

    enum Phase {
        case idle
        /// The owl is inviting or answering; the cards are not the child's yet.
        case talking
        /// The cards are up and the child may tap one.
        case choosing
    }

    private(set) var phase: Phase = .idle
    var isRunning: Bool { phase != .idle }

    var onLeave: (() -> Void)?

    var captionsEnabled = true {
        didSet { caption.isHidden = !captionsEnabled }
    }

    /// Nothing to offer again: the owl lays out another three by itself, forever, until
    /// the child taps it.
    var againProp: RoomObjectID? { nil }

    // MARK: Tuning

    /// Between the owl finishing an answer and the next three cards arriving. Longer
    /// than the window's beat, because there a child is already forming their own
    /// question and here they are waiting to be shown something.
    var beatAfterAnswer: TimeInterval = 1.1

    /// Over by the basket.
    var wonderingSpot = RoomLayout.approachPoint(for: .basket)

    /// Left of the owl and clear of it. Three cards and their gaps are 968 points wide,
    /// so this row runs from x 76 to x 1044 and the owl stands past its right edge.
    var cardsCentre = CGPoint(x: 560, y: 300)

    var choiceCount = 3

    // MARK: Collaborators

    private let scene: SKScene
    private let owl: OwlNode
    private let pack: ContentPack
    private let voice: OwlVoice
    private let choices: SpokenChoices

    private let backdrop = ModeBackdrop()
    private let caption = CaptionNode(maxWidth: 820, fontSize: 44)

    // MARK: Turn state

    private enum Utterance { case invite, answer }
    private var utterance: Utterance = .invite

    /// The questions currently on the cards, in the order they are shown.
    private var offered: [Question] = []
    /// The last few laid out or answered, so a child does not get the same three twice
    /// running.
    private var recentlyUsed: [String] = []

    private var scheduled: [DispatchWorkItem] = []

    // MARK: Init

    init(scene: SKScene, owl: OwlNode, pack: ContentPack, voice: OwlVoice) {
        self.scene = scene
        self.owl = owl
        self.pack = pack
        self.voice = voice
        self.choices = SpokenChoices(scene: scene, voice: voice, language: pack.language)

        caption.position = CGPoint(x: 470, y: 820)
        caption.zPosition = ModeLayer.overlay

        choices.onPick = { [weak self] index in self?.cardTapped(index) }
        // Naming the cards is the owl talking; once it stops it is waiting on the child.
        // `.listening` is ear tufts up and leaning in, which is what waiting looks like —
        // the microphone is not open here and never is. Word games do the same after
        // their cards, and `.thinking` would shut the owl's eyes while a child chooses.
        choices.onNamed = { [weak self] in self?.owl.transition(to: .listening) }
    }

    var canBegin: Bool { !pack.questions.isEmpty }

    // MARK: Starting and stopping

    func begin() {
        guard phase == .idle, canBegin else { return }

        backdrop.show(in: scene)

        owl.zPosition = ModeLayer.owl
        if caption.parent == nil { scene.addChild(caption) }

        voice.onWordRange = { [weak self] range in self?.caption.highlight(range: range) }
        voice.onMouth = { [weak self] openness in self?.owl.setMouthOpenness(openness) }
        voice.onFinished = { [weak self] in self?.owlFinishedSpeaking() }

        owl.travel(to: wonderingSpot)
        invite()
    }

    func leave() {
        guard phase != .idle else { return }
        cancelScheduled()

        voice.stop()
        owl.setMouthOpenness(0)
        choices.dismiss()

        caption.clear()
        caption.removeFromParent()

        offered = []
        recentlyUsed.removeAll()
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

    // MARK: Offering

    /// Said once at the top. A pack with no `wonderInvite` line goes straight to the
    /// cards rather than standing there in silence — `SpokenChoices` names each one
    /// aloud anyway, so a child is never left with three pictures and no voice.
    private func invite() {
        phase = .talking
        caption.clear()

        guard let line = pack.phrase(.wonderInvite) else {
            layOutCards()
            return
        }
        speak(line, as: .invite)
    }

    private func speak(_ line: any Speakable, as utterance: Utterance) {
        self.utterance = utterance
        owl.transition(to: .speaking)
        voice.say(line)
    }

    private func owlFinishedSpeaking() {
        guard isRunning else { return }

        switch utterance {
        case .invite:
            layOutCards()
        case .answer:
            after(beatAfterAnswer) { [weak self] in self?.invite() }
        }
    }

    private func layOutCards() {
        let picks = pickQuestions()
        guard !picks.isEmpty else {
            after(beatAfterAnswer) { [weak self] in self?.invite() }
            return
        }
        phase = .choosing
        owl.transition(to: .speaking)
        caption.clear()
        offered = picks
        picks.forEach { remember($0.id) }

        let options = picks.map { question in
            SpokenChoices.Option(
                line: SpokenText(id: question.id, text: question.text,
                                 stem: "question_\(question.id)_prompt"),
                illustration: "question_\(question.id).png"
            )
        }
        choices.present(options, centre: cardsCentre)
    }

    private func cardTapped(_ index: Int) {
        guard phase == .choosing, offered.indices.contains(index) else { return }
        choices.dismiss()
        answer(offered[index])
    }

    // MARK: Answering

    private func answer(_ question: Question) {
        phase = .talking
        caption.show(question.answer)
        caption.alpha = 0
        caption.run(.fadeIn(withDuration: 0.25))
        owl.transition(to: .happy)
        speak(question.answerLine, as: .answer)
    }

    // MARK: Picking

    private func pickQuestions() -> [Question] {
        let fresh = pack.questions.filter { !recentlyUsed.contains($0.id) }
        let pool = fresh.count >= choiceCount ? fresh : pack.questions
        return Array(pool.shuffled().prefix(choiceCount))
    }

    private func remember(_ id: String) {
        recentlyUsed.append(id)
        let window = max(1, min(24, pack.questions.count - choiceCount))
        if recentlyUsed.count > window { recentlyUsed.removeFirst() }
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
