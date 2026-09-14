import SpriteKit

/// "Why?": the child taps the window and asks the owl a question.
///
/// Tap the window → the owl flies up to it → "Ask me anything you like." → the child asks
/// → the owl either knows, or says it does not and sends them to a grown-up. Then it asks
/// for another. Tapping the owl leaves.
///
/// **Every answer is a sentence somebody wrote**, sitting in the content pack;
/// `QuestionMatcher` picks one or picks none. A miss says the `unknownQuestion` line and
/// means it — an owl that makes something up for a five-year-old is worse than one that
/// admits it does not know.
///
/// There is one exception, and it is not in the App Store build. With `LITTLE_OWL_AI`
/// compiled in, a parent who has entered their own API key can let the owl ask a model
/// on a miss instead of stopping there. Everything about that lives behind `OwlBrain`,
/// including the reasoning for it; what matters here is that it changes nothing else.
/// The bank still answers first, the guard still throws away anything that is not a
/// plain spoken sentence, and a refusal, a timeout or no network at all lands on exactly
/// the `unknownQuestion` line the child would have heard anyway.
///
/// On a device that cannot recognise speech, the child taps one of three questions the
/// owl reads aloud instead. They get real answers; they just cannot ask anything they
/// like.
final class WhyMode: RoomMode {

    enum Phase {
        case idle
        /// The owl is inviting or answering.
        case talking
        /// The child's turn, out loud.
        case listening
        /// The child's turn, by tapping.
        case choosing
    }

    private(set) var phase: Phase = .idle
    var isRunning: Bool { phase != .idle }

    var onLeave: (() -> Void)?

    /// Captions are the only text a child ever sees, and a parent can turn them off.
    var captionsEnabled = true {
        didSet { caption.isHidden = !captionsEnabled }
    }

    /// Nothing to offer again: the owl asks for another question by itself, forever,
    /// until the child taps it.
    var againProp: RoomObjectID? { nil }

    // MARK: Tuning

    var beatBeforeListening: TimeInterval = 0.35
    var beatAfterAnswer: TimeInterval = 0.9

    /// How long the owl waits for a child who has tapped the window and not asked yet.
    /// Longer than elsewhere: thinking of a question takes a moment.
    var patience: TimeInterval = 10

    /// Up at the window, which is where the mode lives.
    var askingSpot = RoomLayout.approachPoint(for: .window)

    /// The question cards go low, clear of the owl up at the window and off the side
    /// table at the left edge.
    var choicesCentre = CGPoint(x: 640, y: 255)

    /// How many questions the no-recognition path offers at a time.
    var choiceCount = 3

    // MARK: Collaborators

    private let scene: SKScene
    private let owl: OwlNode
    private let pack: ContentPack
    private let voice: OwlVoice
    private let matcher: QuestionMatcher
    private let turn: ListeningTurn
    private let choices: SpokenChoices

    /// Nil in any build without `LITTLE_OWL_AI`, and nil in one that has it until a
    /// parent has both turned it on and entered a key. Nothing downstream of here knows
    /// which of those it is.
    private let brain: OwlBrain?

    /// Guards against a slow answer arriving after the child has walked away, or after
    /// they asked something else. Bumped on every question; an answer whose stamp does
    /// not match is dropped.
    private var askCount = 0

    private let backdrop = ModeBackdrop()
    private let caption = CaptionNode(maxWidth: 820, fontSize: 44)
    private let halo: SKShapeNode

    // MARK: Turn state

    private enum Utterance { case invite, answer, unknown, chooseInvite }
    private var utterance: Utterance = .invite

    /// The questions currently on the cards, in the order they are shown.
    private var offered: [Question] = []
    /// The last few offered or answered, so the cards are not the same three every time.
    private var recentlyUsed: [String] = []

    private var scheduled: [DispatchWorkItem] = []

    // MARK: Init

    init(scene: SKScene, owl: OwlNode, pack: ContentPack, voice: OwlVoice) {
        self.scene = scene
        self.owl = owl
        self.pack = pack
        self.voice = voice
        self.matcher = QuestionMatcher(pack.questions)
        self.turn = ListeningTurn(recognitionLocale: pack.recognitionLocale)
        self.choices = SpokenChoices(scene: scene, voice: voice, language: pack.language)
        self.brain = Self.makeBrain()

        halo = ListeningHalo.make()

        caption.position = CGPoint(x: 470, y: 820)
        caption.zPosition = ModeLayer.overlay

        choices.onPick = { [weak self] index in self?.cardTapped(index) }
        // The owl is talking while it reads the cards, and waiting once it stops.
        choices.onNamed = { [weak self] in self?.owl.transition(to: .listening) }
    }

    var canBegin: Bool { !pack.questions.isEmpty }

    // MARK: Starting and stopping

    func begin() {
        guard phase == .idle, canBegin else { return }
        turn.prepare()
        turn.patience = patience

        backdrop.show(in: scene)

        owl.zPosition = ModeLayer.owl
        if halo.parent == nil { owl.addChild(halo) }
        if caption.parent == nil { scene.addChild(caption) }

        voice.onWordRange = { [weak self] range in self?.caption.highlight(range: range) }
        voice.onMouth = { [weak self] openness in self?.owl.setMouthOpenness(openness) }
        voice.onFinished = { [weak self] in self?.owlFinishedSpeaking() }

        owl.travel(to: askingSpot)
        invite()
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

    // MARK: Asking

    private func invite() {
        phase = .talking
        caption.clear()

        guard let line = pack.phrase(.askInvite) else {
            openChildTurn()
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
            if turn.canHear {
                after(beatBeforeListening) { [weak self] in self?.openChildTurn() }
            } else if let line = pack.phrase(.chooseInvite) {
                speak(line, as: .chooseInvite)
            } else {
                showChoices()
            }

        case .chooseInvite:
            showChoices()

        case .answer, .unknown:
            // Straight back to waiting for the next one. A child with a question has
            // another one right behind it.
            after(beatAfterAnswer) { [weak self] in self?.invite() }
        }
    }

    // MARK: Asking out loud

    private func openChildTurn() {
        guard phase == .talking else { return }
        phase = .listening
        owl.transition(to: .listening)
        ListeningHalo.show(halo)

        turn.begin(fallbackPause: 5) { [weak self] outcome in
            self?.closeChildTurn(outcome)
        }
    }

    private func closeChildTurn(_ outcome: ListeningTurn.Outcome) {
        guard phase == .listening else { return }
        ListeningHalo.hide(halo)

        switch outcome {
        case .heard(let heard):
            guard let question = matcher.question(for: heard) else {
                handleMiss(heard)
                return
            }
            answer(question)

        case .nothing:
            // A child who tapped the window and said nothing has not asked a question,
            // so there is nothing to answer. The owl asks again rather than guessing.
            after(0.3) { [weak self] in self?.invite() }

        case .waited:
            showChoices()
        }
    }

    // MARK: Answering

    private func answer(_ question: Question) {
        phase = .talking
        remember(question.id)
        caption.show(question.answer)
        caption.alpha = 0
        caption.run(.fadeIn(withDuration: 0.25))
        owl.transition(to: .happy)
        speak(question.answerLine, as: .answer)
    }

    /// Nothing in the bank fits.
    ///
    /// In the App Store build that is the end of it and the owl says so. In a build with
    /// a brain and a parent who switched it on, the owl thinks about it first — and if
    /// thinking gets it nowhere, says exactly the same thing.
    private func handleMiss(_ heard: String) {
        guard let brain, ParentSettings.shared.brainEnabled else {
            sayUnknown()
            return
        }

        phase = .talking
        askCount += 1
        let stamp = askCount

        // The hum is not decoration: it covers the wait, so a child never sees a frozen
        // owl while a request is out.
        owl.transition(to: .thinking)
        caption.clear()

        Task { [weak self] in
            let answer = await brain.answer(to: heard)
            // Back to the main queue the way the rest of this file does it, rather than
            // through an actor hop: everything here touches SpriteKit.
            DispatchQueue.main.async {
                guard let self, self.phase == .talking, self.askCount == stamp else { return }
                guard let answer else {
                    self.sayUnknown()
                    return
                }
                self.sayGenerated(answer)
            }
        }
    }

    /// Built once, here, so that everything above this line is the same code in every
    /// build and the difference is a single function that returns nil.
    private static func makeBrain() -> OwlBrain? {
        #if LITTLE_OWL_AI
        guard let key = BrainKey.current else { return nil }
        return AnthropicOwlBrain(key: key)
        #else
        return nil
        #endif
    }

    /// An answer that has no recording and never will, so it is spoken rather than
    /// played. `SpokenText` with no stem is exactly the case `OwlVoice` already falls
    /// back on per line.
    private func sayGenerated(_ answer: String) {
        phase = .talking
        caption.show(answer)
        caption.alpha = 0
        caption.run(.fadeIn(withDuration: 0.25))
        owl.transition(to: .happy)
        speak(SpokenText(id: "brain", text: answer, stem: ""), as: .answer)
    }

    /// Nothing in the bank fits and nothing else will answer. The owl says so, and sends
    /// the child to a grown-up.
    private func sayUnknown() {
        phase = .talking
        guard let line = pack.phrase(.unknownQuestion) else {
            after(beatAfterAnswer) { [weak self] in self?.invite() }
            return
        }
        caption.show(line.text)
        caption.alpha = 0
        caption.run(.fadeIn(withDuration: 0.25))
        speak(line, as: .unknown)
    }

    // MARK: Asking by tapping

    private func showChoices() {
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
        choices.present(options, centre: choicesCentre)
    }

    private func cardTapped(_ index: Int) {
        guard phase == .choosing, offered.indices.contains(index) else { return }
        choices.dismiss()
        answer(offered[index])
    }

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
