import AVFoundation

/// Plays a buffer or a file through the speaker, optionally shifted in pitch, and
/// reports the envelope of what is actually coming out.
///
/// Two callers with the same needs: Echo replays the child's own voice pitched up, and
/// the owl's voice plays the recorded content lines straight. Both want the real output
/// envelope to drive the beak, so they share this rather than each growing an engine.
///
/// `AVAudioUnitTimePitch` does the two jobs independently: `pitch` in cents without
/// changing speed, `rate` as speed without changing pitch. At the defaults it is a
/// pass-through.
final class VoicePlayer {

    /// Smoothed 0...1 envelope of what is actually coming out of the speaker, on the
    /// main queue. This is what drives the owl's beak.
    var onLevel: ((Float) -> Void)?

    /// Main queue, once, when the last sample has been heard.
    var onFinished: (() -> Void)?

    /// Main queue, once, when playback starts, carrying how long it will take at the
    /// current rate. Stories use it to pace captions against a recording that carries
    /// no word timings of its own.
    var onStarted: ((TimeInterval) -> Void)?

    /// Cents. Echo sets +600 — six semitones. Zero leaves the voice alone.
    var pitchCents: Float = 0

    /// Playback speed without changing pitch. Echo sets 1.08.
    var rate: Float = 1

    /// 0...1, what the parent set. Applied to the player node, so the level tap on the
    /// mixer measures the quieter signal — which is why `installLevelTap` divides it back
    /// out. A parent turning the owl down must not also stop its beak moving.
    var volume: Float = 1 {
        didSet { player.volume = clampedVolume }
    }

    private var clampedVolume: Float { min(max(volume, 0), 1) }

    private(set) var isPlaying = false

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let timePitch = AVAudioUnitTimePitch()
    private var smoothedLevel: Float = 0
    private var isTapped = false

    init() {
        engine.attach(player)
        engine.attach(timePitch)
    }

    /// Reads a file into memory and plays it. Used for the owl's recorded content lines,
    /// which are short enough that streaming would buy nothing.
    @discardableResult
    func play(contentsOf url: URL) -> Bool {
        guard let file = try? AVAudioFile(forReading: url),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil,
              buffer.frameLength > 0 else { return false }
        play(buffer)
        return true
    }

    func play(_ buffer: AVAudioPCMBuffer) {
        stop()

        timePitch.pitch = pitchCents
        timePitch.rate = rate
        player.volume = clampedVolume
        smoothedLevel = 0

        let format = buffer.format
        engine.connect(player, to: timePitch, format: format)
        engine.connect(timePitch, to: engine.mainMixerNode, format: format)

        installLevelTap()

        do {
            engine.prepare()
            try engine.start()
        } catch {
            removeLevelTap()
            finish()
            return
        }

        isPlaying = true

        let seconds = Double(buffer.frameLength) / buffer.format.sampleRate / Double(max(rate, 0.01))
        DispatchQueue.main.async { [weak self] in self?.onStarted?(seconds) }

        // `.dataPlayedBack` fires when the audio has actually been heard, not merely
        // handed to the renderer.
        player.scheduleBuffer(buffer, at: nil, options: [], completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async { self?.finish() }
        }
        player.play()
    }

    func stop() {
        guard isPlaying else {
            removeLevelTap()
            return
        }
        isPlaying = false
        player.stop()
        removeLevelTap()
        engine.stop()
        reportLevel(0)
    }

    // MARK: Internals

    private func finish() {
        guard isPlaying else { return }
        isPlaying = false
        player.stop()
        removeLevelTap()
        engine.stop()
        reportLevel(0)
        onFinished?()
    }

    private func installLevelTap() {
        guard !isTapped else { return }
        isTapped = true
        let mixer = engine.mainMixerNode
        mixer.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            guard let self else { return }
            // Divided back out: the tap is downstream of the player's volume, so a
            // quiet owl would otherwise read as a still one.
            let heard = buffer.meanSquareLevel() / max(self.clampedVolume, 0.08)
            let target = VoiceRecorder.normalise(heard)
            // Opens fast and closes slower: a beak that snaps shut between syllables
            // reads as a glitch, one that lags a little reads as a mouth.
            self.smoothedLevel += (target - self.smoothedLevel) * (target > self.smoothedLevel ? 0.6 : 0.22)
            self.reportLevel(self.smoothedLevel)
        }
    }

    private func removeLevelTap() {
        guard isTapped else { return }
        isTapped = false
        engine.mainMixerNode.removeTap(onBus: 0)
    }

    private func reportLevel(_ level: Float) {
        DispatchQueue.main.async { [weak self] in self?.onLevel?(level) }
    }
}
