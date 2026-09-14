import SpriteKit

/// Prayers and rhymes: the owl says a line, waits, and the child says it back.
///
/// The turn is: tap the lamp → the room dims and the cards come up → tap one → the owl
/// says the first line → the whole line lights up and a ring appears round the owl,
/// which is how a child who cannot read is told it is their turn → they say it → the owl
/// praises them and moves on. At the end the lamp glows and tapping it starts the set
/// again. Tapping the owl leaves, at any point.
///
/// Two things this mode is careful never to do.
///
/// **It does not grade.** Recognition answers one question — did the child say something
/// of roughly the right length — and `RepeatJudge` is deliberately generous about it. The
/// owl has no "wrong" branch to take.
///
/// **It does not need to hear.** Recognition is a bonus laid on top of a mode that works
/// without it: with no recogniser, no on-device model, or no microphone permission, the
/// owl waits a pause scaled to the line and then praises. Every child gets the same
/// prayer; some devices just listen while it happens.
final class SpokenSetMode: RoomMode {

    enum Phase {
        case idle
        case choosing
        /// The owl is saying a line.
        case saying
        /// The child's turn.
        case listening
        /// The owl is talking between turns: praising, or nudging before a repeat.
        case between
        /// The set is over and the lamp is offering it again.
        case finished
    }

    private(set) var phase: Phase = .idle
    var isRunning: Bool { phase != .idle }

    var onLeave: (() -> Void)?

    /// True while the set is over and the lamp is the way to hear it again.
    var againProp: RoomObjectID? { phase == .finished ? .lamp : nil }

    /// The scene lifts the lamp above the dimming and lets it glow while this is on.
    var onOfferAgain: ((Bool) -> Void)?

    // MARK: Tuning

    /// The brief's number. Silence this long and the owl says the line again.
    var silencePatience: TimeInterval = 8

    /// How long a child may keep going in one breath before the turn ends anyway.
    var longestChildTurn: TimeInterval = 12

    /// Silence after the child has been talking that ends their turn. A shade longer
    /// than Echo's: a recitation has pauses in it that a played-back giggle does not.
    var silenceToFinishTurn: TimeInterval = 1.25

    /// A beat between the owl finishing a line and the child's turn opening, so the two
    /// do not run into each other.
    var beatBeforeChildTurn: TimeInterval = 0.4

    /// A beat between one line ending and the next beginning.
    var beatBetweenLines: TimeInterval = 0.55

    /// Where the owl settles for the whole set: beside the lamp it was sent to, which
    /// keeps it obvious which object this mode belongs to.
    var recitingSpot = RoomLayout.approachPoint(for: .lamp)

    // MARK: Collaborators

    private let scene: SKScene
    private let owl: OwlNode
    private let pack: ContentPack
    private let voice: OwlVoice
    private let settings: ParentSettings

    private let recorder = VoiceRecorder()
    private let listener: SpeechListener

    private let dim = SKSpriteNode(color: SKColor(white: 0.03, alpha: 1), size: RoomLayout.designSize)
    private let caption = CaptionNode(maxWidth: 900, fontSize: 52)
    private let halo: SKShapeNode
    private var picker: SpokenSetPicker?

    // MARK: Turn state

    private var set: SpokenSet?
    private var lineIndex = 0
    /// Whether the owl has already offered the current line a second time. The brief
    /// allows exactly one gentle repeat, and then it moves on whatever happens.
    private var hasRepeatedLine = false

    /// Whether this session can hear at all. Resolved once, when the lamp is tapped.
    private var canHear = false

    /// Which of the owl's lines is in the air. Every one of them ends in
    /// `voice.onFinished`, and what happens next depends entirely on which it was — so
    /// it is tracked rather than inferred from the phase, which cannot tell a praise
    /// from a nudge.
    private enum Utterance { case invitation, line, praise, nudge, farewell }
    private var utterance: Utterance = .line

    private var scheduled: [DispatchWorkItem] = []

    // MARK: Init

    init(scene: SKScene, owl: OwlNode, pack: ContentPack, voice: OwlVoice,
         settings: ParentSettings = .shared) {
        self.scene = scene
        self.owl = owl
        self.pack = pack
        self.voice = voice
        self.settings = settings
        self.listener = SpeechListener(locale: pack.recognitionLocale)

        halo = SKShapeNode(circleOfRadius: RoomLayout.owlHeight * 0.60)
        halo.strokeColor = SKColor(hex: 0xFFE6B0).withAlphaComponent(0.6)
        halo.fillColor = .clear
        halo.lineWidth = 7
        halo.position = CGPoint(x: 0, y: RoomLayout.owlHeight * 0.5)
        halo.zPosition = -1
        halo.alpha = 0

        dim.position = CGPoint(x: RoomLayout.designSize.width / 2,
                               y: RoomLayout.designSize.height / 2)
        dim.zPosition = ModeLayer.dim
        dim.alpha = 0

        caption.position = CGPoint(x: 860, y: 660)
        caption.zPosition = ModeLayer.overlay

        recorder.onFinished = { [weak self] _, reason in
            self?.childTurnStopped(reason)
        }
    }

    /// The sets a parent has left on the lamp. Empty means the lamp does nothing, which
    /// is a parent's choice rather than a state to work around.
    var availableSets: [SpokenSet] { settings.spokenSets(from: pack) }

    var canBegin: Bool { !availableSets.isEmpty }

    // MARK: Starting and stopping

    func begin() {
        guard phase == .idle, canBegin else { return }

        resolveHearing()

        if dim.parent == nil { scene.addChild(dim) }
        dim.removeAllActions()      // a pending fade-out from a quick exit and re-entry
        dim.run(.fadeAlpha(to: 0.66, duration: 0.35))

        owl.zPosition = ModeLayer.owl
        owl.transition(to: .listening)
        if halo.parent == nil { owl.addChild(halo) }

        showPicker()
    }

    func leave() {
        guard phase != .idle else { return }
        cancelScheduled()

        voice.stop()
        owl.setMouthOpenness(0)
        stopListeningForChild()

        picker?.removeFromParent()
        picker = nil

        caption.clear()
        caption.removeFromParent()
        hideHalo()
        halo.removeFromParent()

        set = nil
        lineIndex = 0
        hasRepeatedLine = false
        phase = .idle
        onOfferAgain?(false)

        voice.onWordRange = nil
        voice.onMouth = nil
        voice.onFinished = nil

        dim.run(.sequence([.fadeOut(withDuration: 0.3), .removeFromParent()]))
        owl.zPosition = RoomLayout.Z.owl
        owl.transition(to: .idle)
        owl.returnHome()

        onLeave?()
    }

    // MARK: Input

    func handleTap(at point: CGPoint) -> Bool {
        guard phase == .choosing else { return false }
        return picker?.handleTap(at: point) ?? false
    }

    /// The lamp was tapped while the set was over: say it again, from the top.
    func againTapped() {
        guard phase == .finished, let set else { return }
        // No invitation the second time. A child who has just been through the whole set
        // has been told how this works.
        recite(set, inviting: false)
    }

    // MARK: Hearing

    /// Works out, once per visit, whether the owl can tell that the child spoke.
    ///
    /// The microphone prompt is **not** asked for here. The brief puts it on the first
    /// tap of the owl and nowhere else, so a child who has never played Echo gets the
    /// pause instead of a permission alert on the lamp. Speech recognition is a separate
    /// permission, and it is only ever asked for once the microphone is already granted —
    /// so it lands on a parent who has already said yes once.
    private func resolveHearing() {
        canHear = false
        guard MicrophonePermission.status == .granted else { return }

        if SpeechListener.isAuthorisationUndetermined {
            SpeechListener.requestAuthorisation { [weak self] granted in
                guard let self, self.isRunning else { return }
                self.canHear = granted && self.listener.isReady
            }
            return
        }
        canHear = listener.isReady
    }

    // MARK: Choosing

    private func showPicker() {
        phase = .choosing

        let sets = availableSets
        // One set on the lamp is not a choice. Start it.
        guard sets.count > 1 else {
            if let only = sets.first { startSet(only) }
            return
        }

        let picker = SpokenSetPicker(sets: sets)
        picker.position = CGPoint(x: RoomLayout.designSize.width / 2, y: 500)
        picker.zPosition = ModeLayer.overlay
        picker.onPick = { [weak self] set in self?.startSet(set) }
        scene.addChild(picker)
        self.picker = picker
    }

    private func startSet(_ set: SpokenSet) {
        guard phase == .choosing else { return }
        picker?.dismiss()
        picker = nil

        owl.travel(to: recitingSpot)
        recite(set, inviting: true)
    }

    // MARK: Reciting

    private func recite(_ set: SpokenSet, inviting: Bool) {
        cancelScheduled()
        onOfferAgain?(false)

        self.set = set
        lineIndex = 0
        hasRepeatedLine = false

        if caption.parent == nil { scene.addChild(caption) }

        voice.onWordRange = { [weak self] range in
            self?.caption.highlight(range: range)
        }
        voice.onMouth = { [weak self] openness in
            self?.owl.setMouthOpenness(openness)
        }
        voice.onFinished = { [weak self] in
            self?.owlFinishedSpeaking()
        }

        // "Say it with me." Said once, at the top of a set: it is the only explanation a
        // child ever gets of what this mode is, and it has to be spoken, not written.
        if inviting, let invite = pack.phrase(.repeatInvite) {
            phase = .saying
            speak(invite, as: .invitation)
        } else {
            sayCurrentLine()
        }
    }

    private var currentLine: SpokenSet.Line? {
        guard let set, set.lines.indices.contains(lineIndex) else { return nil }
        return set.lines[lineIndex]
    }

    private func sayCurrentLine() {
        guard let line = currentLine else {
            finishSet()
            return
        }
        phase = .saying
        caption.show(line.text)
        caption.alpha = 0
        caption.run(.fadeIn(withDuration: 0.25))
        speak(line, as: .line)
    }

    private func speak(_ line: any Speakable, as utterance: Utterance) {
        self.utterance = utterance
        owl.transition(to: .speaking)
        voice.say(line)
    }

    /// One of the owl's lines has ended. Which one decides what happens next.
    private func owlFinishedSpeaking() {
        guard isRunning else { return }

        switch utterance {
        case .invitation:
            after(beatBetweenLines) { [weak self] in self?.sayCurrentLine() }

        case .line:
            // The whole line lights up: "this bit, now, together". A child who cannot
            // read still sees the caption change state, and the ring round the owl says
            // whose turn it is.
            caption.highlightAll()
            after(beatBeforeChildTurn) { [weak self] in self?.openChildTurn() }

        case .praise:
            after(beatBetweenLines) { [weak self] in self?.advance() }

        case .nudge:
            after(beatBeforeChildTurn) { [weak self] in self?.sayCurrentLine() }

        case .farewell:
            owl.transition(to: .idle)
        }
    }

    // MARK: The child's turn

    private func openChildTurn() {
        guard phase == .saying, let line = currentLine else { return }
        phase = .listening
        owl.transition(to: .listening)
        showHalo()

        guard canHear, listener.start() else {
            // The fallback the brief asks for. Nothing is measured, so nothing can fail:
            // the owl simply waits, then takes the child's word for it.
            after(RepeatJudge.fallbackPause(forLineOf: RepeatJudge.wordCount(of: line.text))) {
                [weak self] in self?.closeChildTurn(heard: nil, heardByEar: false)
            }
            return
        }

        recorder.retainsAudio = false        // nothing to play back, so nothing is kept
        recorder.onBuffer = { [weak self] buffer in self?.listener.append(buffer) }
        recorder.patienceBeforeSpeech = silencePatience
        recorder.silenceToFinish = silenceToFinishTurn
        recorder.maximumDuration = longestChildTurn
        recorder.start()
    }

    private func childTurnStopped(_ reason: VoiceRecorder.StopReason) {
        guard phase == .listening else { return }

        switch reason {
        case .silence, .maxDuration:
            listener.finish { [weak self] heard in
                self?.closeChildTurn(heard: heard, heardByEar: true)
            }

        case .noSpeech:
            listener.cancel()
            closeChildTurn(heard: nil, heardByEar: true)

        case .cancelled:
            listener.cancel()

        case .failed:
            // The microphone went away mid-turn. Fall back for the rest of the visit
            // rather than letting a child recite to an owl that cannot hear.
            listener.cancel()
            canHear = false
            closeChildTurn(heard: nil, heardByEar: false)
        }
    }

    private func closeChildTurn(heard: String?, heardByEar: Bool) {
        guard phase == .listening, let line = currentLine else { return }
        stopListeningForChild()
        hideHalo()

        // Without recognition there is nothing to judge, and judging was never the
        // point: the owl waited, so the child said it.
        let outcome = heardByEar ? RepeatJudge.judge(line: line.text, heard: heard) : .repeated

        switch outcome {
        case .repeated:
            praise()

        case .notEnough where !hasRepeatedLine:
            hasRepeatedLine = true
            sayLineAgain()

        case .notEnough:
            // Twice offered. Moving on is the gentlest thing left: no correction, no
            // "wrong", and no child waited out by a toy.
            advance()
        }
    }

    private func stopListeningForChild() {
        recorder.stop(reason: .cancelled)
        recorder.onBuffer = nil
        listener.cancel()
    }

    // MARK: Between lines

    private func praise() {
        phase = .between
        owl.transition(to: .happy)

        guard let praise = pack.phrase(.praise) else {
            after(beatBetweenLines) { [weak self] in self?.advance() }
            return
        }
        speak(praise, as: .praise)
    }

    /// The gentle repeat: a nudge, then the same line over again.
    private func sayLineAgain() {
        guard let nudge = pack.phrase(.nudge) else {
            sayCurrentLine()
            return
        }
        phase = .between
        speak(nudge, as: .nudge)
    }

    private func advance() {
        guard isRunning, set != nil else { return }
        lineIndex += 1
        hasRepeatedLine = false
        sayCurrentLine()
    }

    private func finishSet() {
        phase = .finished
        caption.clear()
        owl.transition(to: .happy)
        onOfferAgain?(true)

        guard let again = pack.phrase(.setAgain) else {
            owl.transition(to: .idle)
            return
        }
        after(0.45) { [weak self] in
            guard let self, self.phase == .finished else { return }
            self.speak(again, as: .farewell)
        }
    }

    // MARK: The listening ring

    private func showHalo() {
        halo.removeAllActions()
        halo.setScale(1)
        halo.run(.fadeAlpha(to: 0.75, duration: 0.2))
        halo.run(.repeatForever(.sequence([
            .group([.scale(to: 1.06, duration: 0.9), .fadeAlpha(to: 0.45, duration: 0.9)]),
            .group([.scale(to: 1.00, duration: 0.9), .fadeAlpha(to: 0.75, duration: 0.9)])
        ])), withKey: "pulse")
    }

    private func hideHalo() {
        halo.removeAction(forKey: "pulse")
        halo.run(.fadeOut(withDuration: 0.25))
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
