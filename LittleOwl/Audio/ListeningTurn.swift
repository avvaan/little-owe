import AVFoundation

/// One turn of listening to the child.
///
/// Three modes want the same thing: open the microphone, let the child talk, and come
/// back with either what they said or the fact that nothing could be heard. The
/// turn-taking lives in `VoiceRecorder` and the recognition in `SpeechListener`; this is
/// the seam that puts the two together, works out once whether this device can hear at
/// all, and guarantees exactly one outcome per turn.
///
/// **Nothing is kept.** `retainsAudio` is off, so no buffer is ever copied or held: the
/// live tap goes straight to on-device recognition and is gone. The transcript lives for
/// the length of one turn and is handed to the caller, which uses it and drops it.
final class ListeningTurn {

    enum Outcome: Equatable {
        /// Recognition heard this.
        case heard(String)
        /// The microphone was open and nothing came back.
        case nothing
        /// The owl could not listen at all, so it waited a pause instead. A mode treats
        /// this as the child having answered — never as a failure, and never as a wrong
        /// answer.
        case waited
    }

    // MARK: Tuning

    /// How long to wait for a child who has not started talking. The brief's number for
    /// Prayers; the other modes are equally patient.
    var patience: TimeInterval = 8

    /// Silence after the child has been talking that ends their turn.
    var silenceToFinish: TimeInterval = 1.25

    /// How long a child may keep going in one breath.
    var longestTurn: TimeInterval = 12

    /// Whether this visit can hear. Resolved by `prepare()` and turned off for good if
    /// the microphone fails mid-visit.
    private(set) var canHear = false

    private(set) var isListening = false

    // MARK: Internals

    private let recorder = VoiceRecorder()
    private let listener: SpeechListener
    private var completion: ((Outcome) -> Void)?
    private var fallback: DispatchWorkItem?

    init(recognitionLocale: String) {
        listener = SpeechListener(locale: recognitionLocale)
        recorder.onFinished = { [weak self] _, reason in
            self?.recordingStopped(reason)
        }
    }

    // MARK: Permission

    /// Works out, once per visit to a mode, whether the owl can tell that the child
    /// spoke.
    ///
    /// The microphone prompt is **not** asked for here. The brief puts it on the first
    /// tap of the owl and nowhere else, so a child who has never played Echo gets the
    /// fallback rather than a permission alert on a lamp or a window. Speech recognition
    /// is a separate permission and is only ever asked for once the microphone is
    /// already granted — so it lands on a parent who has already said yes once.
    func prepare() {
        canHear = false
        guard MicrophonePermission.status == .granted else { return }

        if SpeechListener.isAuthorisationUndetermined {
            SpeechListener.requestAuthorisation { [weak self] granted in
                guard let self else { return }
                self.canHear = granted && self.listener.isReady
            }
            return
        }
        canHear = listener.isReady
    }

    // MARK: A turn

    /// `fallbackPause` is used only when the owl cannot hear.
    func begin(fallbackPause: TimeInterval, _ completion: @escaping (Outcome) -> Void) {
        cancel()
        self.completion = completion
        isListening = true

        guard canHear, listener.start() else {
            let item = DispatchWorkItem { [weak self] in self?.finish(.waited) }
            fallback = item
            DispatchQueue.main.asyncAfter(deadline: .now() + fallbackPause, execute: item)
            return
        }

        recorder.retainsAudio = false
        recorder.onBuffer = { [weak self] buffer in self?.listener.append(buffer) }
        recorder.patienceBeforeSpeech = patience
        recorder.silenceToFinish = silenceToFinish
        recorder.maximumDuration = longestTurn
        recorder.start()
    }

    /// Drops the turn without reporting anything.
    func cancel() {
        completion = nil
        fallback?.cancel()
        fallback = nil
        stopEverything()
        isListening = false
    }

    private func recordingStopped(_ reason: VoiceRecorder.StopReason) {
        guard isListening else { return }

        switch reason {
        case .silence, .maxDuration:
            listener.finish { [weak self] heard in
                guard let heard else {
                    self?.finish(.nothing)
                    return
                }
                self?.finish(.heard(heard))
            }

        case .noSpeech:
            listener.cancel()
            finish(.nothing)

        case .cancelled:
            listener.cancel()

        case .failed:
            // The microphone went away. Fall back for the rest of the visit rather than
            // letting a child talk to an owl that cannot hear.
            listener.cancel()
            canHear = false
            finish(.waited)
        }
    }

    private func finish(_ outcome: Outcome) {
        guard let completion else { return }
        self.completion = nil
        fallback?.cancel()
        fallback = nil
        stopEverything()
        isListening = false
        completion(outcome)
    }

    private func stopEverything() {
        recorder.stop(reason: .cancelled)
        recorder.onBuffer = nil
        listener.cancel()
    }
}
