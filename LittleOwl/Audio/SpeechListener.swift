import AVFoundation
import Speech

/// On-device speech recognition, and nothing else.
///
/// `requiresOnDeviceRecognition` is set to true and a task is **never started without
/// it**. If a device cannot recognise this language on device, this type reports itself
/// unavailable and the mode above takes its fallback path. There is deliberately no
/// server fallback to take: a server fallback is a network call, and this app makes
/// none.
///
/// It is also thin on purpose about what it reports. Prayers only needs to know *that*
/// the child said something of roughly the right length — never whether they said it
/// correctly. The transcript is held for the length of one turn, is never written down,
/// never shown, and never leaves this process.
final class SpeechListener {

    /// Why the owl might not be able to hear. Every one of these ends in the same place:
    /// the fallback, which is a mode that works without a microphone at all.
    enum Availability: Equatable {
        case ready
        /// No recogniser at all for the pack's language.
        case noRecogniser
        /// The device would need a server for this language, so the app will not do it.
        case needsServer
        /// Speech recognition has not been allowed.
        case notAuthorised
    }

    private let recogniser: SFSpeechRecognizer?

    /// Touched from the audio tap queue as well as the main queue, so it is behind a lock.
    private let requestLock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    private var task: SFSpeechRecognitionTask?
    private var latest: String?
    private var completion: ((String?) -> Void)?
    private var deadline: DispatchWorkItem?

    /// How long to wait for the final transcript after the child stops talking. The
    /// partial results are already good enough to know they spoke, so a child never
    /// waits on the recogniser tidying up.
    var settleAfterSpeech: TimeInterval = 0.7

    init(locale identifier: String) {
        recogniser = SFSpeechRecognizer(locale: Locale(identifier: identifier))
    }

    // MARK: Permission
    //
    // This is a second prompt, separate from the microphone. The mode only ever reaches
    // it once the microphone is already granted, so it lands on a parent who has already
    // said yes once rather than on a cold first tap.

    static var isAuthorised: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    static var isAuthorisationUndetermined: Bool {
        SFSpeechRecognizer.authorizationStatus() == .notDetermined
    }

    /// Completion is always delivered on the main queue.
    static func requestAuthorisation(_ completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async { completion(status == .authorized) }
        }
    }

    // MARK: Availability

    var availability: Availability {
        guard let recogniser else { return .noRecogniser }
        guard recogniser.supportsOnDeviceRecognition else { return .needsServer }
        guard SpeechListener.isAuthorised else { return .notAuthorised }
        return .ready
    }

    var isReady: Bool { availability == .ready }

    // MARK: One turn

    /// Begins a recognition task. Returns false if it could not start, which is not an
    /// error — the caller simply uses the fallback for this turn.
    @discardableResult
    func start() -> Bool {
        cancel()

        guard let recogniser, recogniser.isAvailable, recogniser.supportsOnDeviceRecognition,
              SpeechListener.isAuthorised else { return false }

        let request = SFSpeechAudioBufferRecognitionRequest()
        // The whole privacy story in one line: recognised on the device, or not at all.
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.addsPunctuation = false
        request.taskHint = .dictation

        let task = recogniser.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                let isFinal = result.isFinal
                DispatchQueue.main.async {
                    self.latest = text
                    if isFinal { self.deliver() }
                }
            } else if error != nil {
                // A recogniser that gives up mid-turn is treated as silence, not as a
                // failure the child has to hear about.
                DispatchQueue.main.async { self.deliver() }
            }
        }

        requestLock.lock()
        self.request = request
        requestLock.unlock()
        self.task = task
        return true
    }

    /// Called from the recorder's audio tap queue.
    func append(_ buffer: AVAudioPCMBuffer) {
        requestLock.lock()
        let request = self.request
        requestLock.unlock()
        request?.append(buffer)
    }

    /// Ends the turn. `completion` runs on the main queue exactly once with whatever was
    /// recognised, or nil if that was nothing.
    func finish(_ completion: @escaping (String?) -> Void) {
        guard task != nil else {
            completion(nil)
            return
        }
        self.completion = completion

        requestLock.lock()
        let request = self.request
        self.request = nil
        requestLock.unlock()
        request?.endAudio()

        let deadline = DispatchWorkItem { [weak self] in self?.deliver() }
        self.deadline = deadline
        DispatchQueue.main.asyncAfter(deadline: .now() + settleAfterSpeech, execute: deadline)
    }

    /// Drops the turn and reports nothing.
    func cancel() {
        completion = nil
        deadline?.cancel()
        deadline = nil
        teardown()
    }

    // MARK: Internals

    private func deliver() {
        guard let completion else { return }
        self.completion = nil
        deadline?.cancel()
        deadline = nil

        let heard = latest?.trimmingCharacters(in: .whitespacesAndNewlines)
        teardown()
        completion(heard?.isEmpty == false ? heard : nil)
    }

    private func teardown() {
        requestLock.lock()
        let request = self.request
        self.request = nil
        requestLock.unlock()

        request?.endAudio()
        task?.cancel()
        task = nil
        latest = nil
    }
}
