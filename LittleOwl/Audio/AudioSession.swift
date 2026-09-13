import AVFoundation

/// Owns the app's one `AVAudioSession` and tells interested parties when the system
/// has taken the audio away.
///
/// The category starts at `.playback` and is raised to `.playAndRecord` the first time
/// the microphone is needed. It is never lowered again: switching categories causes an
/// audible glitch, and having one happen mid-sentence every time a child talks to the
/// owl is worse than staying in the record-capable category.
final class AudioSession {

    static let shared = AudioSession()
    private init() {}

    /// Fires when an interruption starts, the route changes in a way that invalidates
    /// capture, or the media server resets. Whoever is recording or playing must stop.
    var onAudioLost: (() -> Void)?

    private(set) var isRecordingCapable = false
    private var isObserving = false

    func configure() {
        apply(category: .playback, options: [])
        observeSystemEvents()
    }

    /// Idempotent. Call before the owl starts listening, not at the moment the tap
    /// lands, so the category switch is covered by the tap sound.
    func prepareForRecording() {
        guard !isRecordingCapable else { return }
        apply(
            category: .playAndRecord,
            // Without `.defaultToSpeaker` a record-capable session comes out of the
            // earpiece, which on an iPad on a table is close to silent.
            options: [.defaultToSpeaker, .allowBluetoothA2DP]
        )
        isRecordingCapable = true
    }

    private func apply(category: AVAudioSession.Category, options: AVAudioSession.CategoryOptions) {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(category, mode: .default, options: options)
            try session.setActive(true, options: [])
        } catch {
            // Nothing useful to do and nothing to show a child. The app keeps working
            // silently rather than failing.
            assertionFailure("Audio session setup failed: \(error)")
        }
    }

    // MARK: System events

    private func observeSystemEvents() {
        guard !isObserving else { return }
        isObserving = true

        let centre = NotificationCenter.default
        centre.addObserver(
            self, selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification, object: nil
        )
        centre.addObserver(
            self, selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification, object: nil
        )
        centre.addObserver(
            self, selector: #selector(handleMediaServicesReset),
            name: AVAudioSession.mediaServicesWereResetNotification, object: nil
        )
    }

    @objc private func handleInterruption(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }

        switch type {
        case .began:
            notifyAudioLost()
        case .ended:
            // Do not resume anything on our own: the child decides what happens next by
            // tapping. Just make the session usable again.
            try? AVAudioSession.sharedInstance().setActive(true, options: [])
        @unknown default:
            notifyAudioLost()
        }
    }

    @objc private func handleRouteChange(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }

        switch reason {
        case .oldDeviceUnavailable, .newDeviceAvailable, .override, .categoryChange:
            // The input format can change with the route, which invalidates a capture
            // already in flight.
            notifyAudioLost()
        default:
            break
        }
    }

    @objc private func handleMediaServicesReset() {
        isRecordingCapable = false
        configure()
        notifyAudioLost()
    }

    private func notifyAudioLost() {
        DispatchQueue.main.async { [weak self] in
            self?.onAudioLost?()
        }
    }
}
