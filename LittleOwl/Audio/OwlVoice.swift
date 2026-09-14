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

    /// Which character range of the line is being said, on the main queue. Stories use
    /// it to light up the caption word by word.
    ///
    /// The synthesiser reports this exactly. A recording carries no word timings, so
    /// the ranges are estimated from the line's duration, weighted by word length —
    /// close enough to follow with a finger, and honestly approximate.
    var onWordRange: ((NSRange) -> Void)?

    private(set) var isSpeaking = false

    /// 0...1, from parent settings. Applied to both paths — the recorded one through the
    /// player, the synthesised one through the utterance — so the owl sounds the same
    /// either way at any setting.
    var volume: Double = 1 {
        didSet { player.volume = Float(min(max(volume, 0), 1)) }
    }

    /// True when the last line spoken had no recording. Parent settings will use this
    /// to tell a family why the owl sounds like a robot.
    private(set) var isUsingSynthesiser = false

    private let language: String
    private let speechLocale: String
    private let bundle: Bundle

    private let player = VoicePlayer()
    private let synthesiser = AVSpeechSynthesizer()
    private var mouthReset: DispatchWorkItem?
    private var wordSchedule: [DispatchWorkItem] = []

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

        if let url = ContentLoader.audioURL(for: line, language: language, in: bundle) {
            player.onStarted = { [weak self] duration in
                self?.scheduleEstimatedWordRanges(for: line.text, over: duration)
            }
            if player.play(contentsOf: url) {
                isUsingSynthesiser = false
                return
            }
        }

        isUsingSynthesiser = true
        let utterance = AVSpeechUtterance(string: line.text)
        utterance.voice = AVSpeechSynthesisVoice(language: speechLocale)
        // Slower and a touch higher than default: this is an owl talking to a
        // three-year-old, not a navigation system.
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.88
        utterance.pitchMultiplier = 1.15
        utterance.volume = Float(min(max(volume, 0), 1))
        utterance.postUtteranceDelay = 0.1
        synthesiser.speak(utterance)
    }

    func stop() {
        mouthReset?.cancel()
        mouthReset = nil
        wordSchedule.forEach { $0.cancel() }
        wordSchedule.removeAll()

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
        wordSchedule.forEach { $0.cancel() }
        wordSchedule.removeAll()
        onMouth?(0)
        onFinished?()
    }

    /// Spreads the line's words across a recording's duration, giving each a share
    /// proportional to its length. A long word takes longer to say than a short one,
    /// which is most of what makes an estimate look right.
    private func scheduleEstimatedWordRanges(for text: String, over duration: TimeInterval) {
        guard duration > 0, onWordRange != nil else { return }

        let words = OwlVoice.wordRanges(in: text)
        let total = words.reduce(0) { $0 + max($1.length, 1) }
        guard total > 0 else { return }

        var elapsed: TimeInterval = 0
        for range in words {
            let at = elapsed
            let item = DispatchWorkItem { [weak self] in self?.onWordRange?(range) }
            wordSchedule.append(item)
            DispatchQueue.main.asyncAfter(deadline: .now() + at, execute: item)
            elapsed += duration * Double(max(range.length, 1)) / Double(total)
        }
    }

    /// Character ranges of the words in a line, in order.
    static func wordRanges(in text: String) -> [NSRange] {
        var ranges: [NSRange] = []
        let ns = text as NSString
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length),
                               options: [.byWords, .substringNotRequired]) { _, range, _, _ in
            ranges.append(range)
        }
        return ranges
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
        onWordRange?(characterRange)

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
