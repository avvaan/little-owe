import AVFoundation

/// Plays the child's own voice back, pitched up and slightly quicker.
///
/// `AVAudioUnitTimePitch` does both jobs independently: `pitch` in cents without
/// changing speed, `rate` as speed without changing pitch. Feeding it +600 cents and
/// 1.08× gives the brief's "higher and a little faster" rather than the chipmunk
/// artefact you get from simply playing a recording fast.
final class EchoPlayer {

    /// Smoothed 0...1 envelope of what is actually coming out of the speaker, on the
    /// main queue. This is what drives the owl's beak.
    var onLevel: ((Float) -> Void)?

    /// Main queue, once, when the last sample has been heard.
    var onFinished: (() -> Void)?

    /// +6 semitones.
    var pitchCents: Float = 600

    /// Just enough to feel playful without eating the words.
    var rate: Float = 1.08

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

    func play(_ buffer: AVAudioPCMBuffer) {
        stop()

        timePitch.pitch = pitchCents
        timePitch.rate = rate
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
            let target = VoiceRecorder.normalise(buffer.meanSquareLevel())
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
