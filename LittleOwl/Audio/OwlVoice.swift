import AVFoundation
import CoreGraphics

/// The owl saying a line of content.
///
/// Every line prefers its recording and falls back to the synthesiser, **per line**
/// rather than per build. That matters more than it sounds: a voice actor delivers in
/// sessions, so the pack is half-recorded for weeks, and a global flag would mean
/// either no real voice at all or silent gaps where a recording is missing.
///
/// Both paths drive the beak. Recorded audio gives a real envelope from the speaker;
/// the synthesiser has no envelope to offer, so the mouth is pulsed per word from
/// `AVSpeechSynthesizerDelegate` — which is crude, and is meant to be, because it
/// disappears the moment a recording exists.
final class OwlVoice: NSObject {

    /// 0...1 beak openness, on the main queue.
    var onMouth: ((CGFloat) -> Void)?

    /// Main queue, once, when the line has finished — or been stopped.
    var onFinished: (() -> Void)?

    private(set) var isSpeaking = false

    /// True when the last line spoken had no recording. Parent settings will use this
    /// to tell a family why the owl sounds like a robot.
    private(set) var isUsingSynthesiser = false

    private let language: String
    private let speechLocale: String
    private let bundle: Bundle

    private let player = VoicePlayer()
    private let synthesiser = AVSpeechSynthesizer()
    private var mouthReset: DispatchWorkItem?

    init(pack: ContentPack, bundle: Bundle = .main) {
        self.language = pack.language
        self.speechLocale = pack.speechLocale
        self.bundle = bundle
        super.init()

        synthesiser.delegate = self
        player.onLevel = { [weak self] level in
            self?.onMouth?(CGFloat(level))
        }
        player.onFinished = { [weak self] in
            self?.finish()
        }
    }

    // MARK: Speaking

    func say(_ line: any Speakable) {
        stop()
        isSpeaking = true

        if let url = ContentLoader.audioURL(for: line, language: language, in: bundle),
           player.play(contentsOf: url) {
            isUsingSynthesiser = false
            return
        }

        isUsingSynthesiser = true
        let utterance = AVSpeechUtterance(string: line.text)
        utterance.voice = AVSpeechSynthesisVoice(language: speechLocale)
        // Slower and a touch higher than default: this is an owl talking to a
        // three-year-old, not a navigation system.
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.88
        utterance.pitchMultiplier = 1.15
        utterance.postUtteranceDelay = 0.1
        synthesiser.speak(utterance)
    }

    func stop() {
        mouthReset?.cancel()
        mouthReset = nil

        player.stop()
        if synthesiser.isSpeaking {
            synthesiser.stopSpeaking(at: .immediate)
        }

        if isSpeaking {
            isSpeaking = false
            onMouth?(0)
        }
    }

    private func finish() {
        guard isSpeaking else { return }
        isSpeaking = false
        mouthReset?.cancel()
        onMouth?(0)
        onFinished?()
    }
}

// MARK: - Synthesiser mouth

extension OwlVoice: AVSpeechSynthesizerDelegate {

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           willSpeakRangeOfSpeechString characterRange: NSRange,
                           utterance: AVSpeechUtterance) {
        // One pulse per word, held roughly as long as the word takes to say. A real
        // envelope this is not; a mouth that moves when words come out, it is.
        onMouth?(0.78)

        mouthReset?.cancel()
        let hold = max(0.08, Double(characterRange.length) * 0.012)
        let reset = DispatchWorkItem { [weak self] in self?.onMouth?(0.12) }
        mouthReset = reset
        DispatchQueue.main.asyncAfter(deadline: .now() + hold, execute: reset)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didFinish utterance: AVSpeechUtterance) {
        finish()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didCancel utterance: AVSpeechUtterance) {
        // `stop()` has already reported the mouth closed and does not fire onFinished:
        // a cancelled line was somebody else's decision, not the line ending.
    }
}
