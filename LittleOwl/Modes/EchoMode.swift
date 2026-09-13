import Foundation
import CoreGraphics

/// Echo: the child taps the owl, talks, and the owl says it back in a sillier voice.
///
/// The default mode. It needs no content pack, no recognition and no network — it is
/// the one thing the owl can always do, and it is the app's whole first impression.
///
/// The turn is: tap → owl listens → child talks → owl thinks for a beat → owl answers.
/// Recording ends when the child stops talking, when they tap again, or at a hard cap.
/// That is turn-taking, not a timeout: the child stays in Echo throughout and can start
/// another turn immediately. Nothing exits on its own.
///
/// **Nothing is stored.** The recording lives in one in-memory buffer owned by
/// `VoiceRecorder` and is released the moment the owl finishes speaking, or the moment
/// anything is cancelled. See `VoiceRecorder` for why that is structural.
final class EchoMode {

    enum Phase {
        case idle
        /// The system permission alert is up. Only ever on the very first owl tap.
        case askingPermission
        case listening
        case thinking
        case speaking
    }

    private(set) var phase: Phase = .idle
    var isRunning: Bool { phase != .idle }

    /// Fires when the microphone cannot be used. Parent settings (deliverable 7) will
    /// surface this; the child is never told, they just get a giggle.
    var onMicrophoneUnavailable: (() -> Void)?

    // MARK: Tuning

    /// A deliberate beat between hearing and answering, so the turn-taking is legible.
    /// The processing itself is instant.
    var thinkingPause: TimeInterval = 0.35

    /// Shorter than this and there is nothing worth echoing.
    var shortestUsefulRecording: TimeInterval = 0.25

    /// How often a turn comes with a giggle.
    var giggleChance: Double = 0.34

    // MARK: Collaborators

    private let owl: OwlNode
    private let recorder = VoiceRecorder()
    private let player = EchoPlayer()

    private var giggleAfterSpeaking = false
    private var scheduled: [DispatchWorkItem] = []

    // MARK: Init

    init(owl: OwlNode) {
        self.owl = owl

        recorder.onFinished = { [weak self] recording, reason in
            self?.recordingFinished(recording, reason)
        }
        player.onLevel = { [weak self] level in
            self?.owl.setMouthOpenness(CGFloat(level))
        }
        player.onFinished = { [weak self] in
            self?.speakingFinished()
        }
    }

    // MARK: Input

    /// The child tapped the owl.
    func handleOwlTap() {
        switch phase {
        case .idle:
            begin()
        case .listening:
            // "I'm done." Treat it exactly like falling silent.
            recorder.stop(reason: .silence)
        case .speaking:
            // Cut the owl off mid-sentence — children do this constantly and it has to
            // feel like the owl simply stopped, not like something broke.
            reset()
        case .thinking, .askingPermission:
            // Under half a second, and an alert the child cannot answer. Ignoring is
            // less jarring than cancelling.
            break
        }
    }

    /// Stops everything and releases the recording. Called when another mode starts,
    /// when the app goes to the background, and when the system takes the audio away.
    func cancel() {
        guard phase != .idle else { return }
        reset()
    }

    // MARK: Turn

    private func begin() {
        switch MicrophonePermission.status {
        case .granted:
            AudioSession.shared.prepareForRecording()
            startListening()

        case .undetermined:
            // The prompt happens here and nowhere else: on the first tap of the owl,
            // with the explanation in NSMicrophoneUsageDescription for the parent.
            phase = .askingPermission
            owl.transition(to: .thinking)
            MicrophonePermission.request { [weak self] granted in
                guard let self, self.phase == .askingPermission else { return }
                guard granted else {
                    self.microphoneUnavailable()
                    return
                }
                AudioSession.shared.prepareForRecording()
                self.startListening()
            }

        case .denied:
            microphoneUnavailable()
        }
    }

    private func startListening() {
        phase = .listening
        owl.transition(to: .listening)
        recorder.start()
    }

    private func recordingFinished(_ recording: VoiceRecorder.Recording?, _ reason: VoiceRecorder.StopReason) {
        guard phase == .listening else { return }

        switch reason {
        case .silence, .maxDuration:
            guard let recording, recording.duration >= shortestUsefulRecording else {
                playfulShrug()
                return
            }
            beginThinking(with: recording)

        case .noSpeech:
            playfulShrug()

        case .cancelled:
            reset()

        case .failed:
            microphoneUnavailable()
        }
    }

    private func beginThinking(with recording: VoiceRecorder.Recording) {
        phase = .thinking
        owl.transition(to: .thinking)
        SoundKit.shared.startLoop(.hum, volumeScale: 0.45, fadeIn: 0.10)

        after(thinkingPause) { [weak self] in
            self?.speak(recording)
        }
    }

    private func speak(_ recording: VoiceRecorder.Recording) {
        guard phase == .thinking else { return }
        SoundKit.shared.stopLoop(.hum, fadeOut: 0.12)

        phase = .speaking
        owl.transition(to: .speaking)

        switch chooseGiggle() {
        case .before:
            let length = SoundKit.shared.playGiggle(volumeScale: 0.9)
            owl.wiggleMouth(for: length)
            // Start the echo just before the giggle finishes: a clean gap between the
            // two reads as two separate events rather than one performance.
            after(length * 0.85) { [weak self] in
                guard let self, self.phase == .speaking else { return }
                self.player.play(recording.buffer)
            }

        case .after:
            giggleAfterSpeaking = true
            player.play(recording.buffer)

        case .none:
            player.play(recording.buffer)
        }
    }

    private func speakingFinished() {
        guard phase == .speaking else { return }

        guard giggleAfterSpeaking else {
            reset()
            return
        }
        giggleAfterSpeaking = false

        let length = SoundKit.shared.playGiggle(volumeScale: 0.9)
        owl.wiggleMouth(for: length)
        after(length) { [weak self] in self?.reset() }
    }

    // MARK: Endings

    /// What the owl does when there is nothing to echo: when the child tapped and said
    /// nothing, or when the microphone is unavailable.
    ///
    /// It never says "wrong", never explains, and never shows the child anything to
    /// read. It giggles and goes back to waiting, which is what a toy does.
    private func playfulShrug() {
        reset()
        let length = SoundKit.shared.playGiggle(volumeScale: 0.8)
        owl.transition(to: .happy)
        owl.wiggleMouth(for: length)
    }

    private func microphoneUnavailable() {
        onMicrophoneUnavailable?()
        playfulShrug()
    }

    /// Stops every moving part and releases the recording.
    private func reset() {
        cancelScheduled()
        giggleAfterSpeaking = false

        recorder.stop(reason: .cancelled)
        player.stop()
        SoundKit.shared.stopLoop(.hum, fadeOut: 0.12)

        owl.stopMouthWiggle()

        phase = .idle
        owl.transition(to: .idle)
    }

    // MARK: Giggles

    private enum GigglePlacement {
        case none
        case before
        case after
    }

    private func chooseGiggle() -> GigglePlacement {
        guard Double.random(in: 0..<1) < giggleChance else { return .none }
        return Bool.random() ? .before : .after
    }

    // MARK: Scheduling

    /// `DispatchWorkItem` rather than `asyncAfter` alone, so a cancelled turn does not
    /// have a stale block wake up half a second later and restart the owl.
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
