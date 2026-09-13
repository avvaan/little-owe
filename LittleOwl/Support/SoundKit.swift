import AVFoundation

/// The sound-effect bank: short one-shots and one looping bed.
///
/// Deliberately `AVAudioPlayer` rather than `SKAction.playSoundFileNamed`. The UX rule
/// is a soft palette with a single volume the parent can trim, and `SKAction` sounds
/// cannot be attenuated. Session configuration lives in `AudioSession`, not here.
final class SoundKit {

    static let shared = SoundKit()
    private init() {}

    /// Effects sit well under the owl's voice. Parent settings will drive this.
    var effectsVolume: Float = 0.55 {
        didSet { loops.values.forEach { $0.volume = effectsVolume * loopScale } }
    }

    private var banks: [Effect: [AVAudioPlayer]] = [:]
    private var loops: [Effect: AVAudioPlayer] = [:]
    private var loopScale: Float = 1.0

    enum Effect: String, CaseIterable {
        case tap     = "tap_soft"
        case hop     = "hop"
        case wake    = "wake"
        case giggleA = "giggle_a"
        case giggleB = "giggle_b"
        /// Seamless loop under the owl's thinking state.
        case hum     = "hum"

        /// The two giggles differ only in whether the pitch rises or falls, so
        /// alternating them keeps the owl from sounding like a sample.
        static var giggles: [Effect] { [.giggleA, .giggleB] }

        /// Everything that is played with `play`. `hum` is excluded: `startLoop`
        /// creates its own player, so banking copies of it would be dead weight.
        static var oneShots: [Effect] { allCases.filter { $0 != .hum } }
    }

    /// `copies` lets the same effect overlap itself when a child taps quickly.
    func preload(_ effects: [Effect] = Effect.oneShots, copies: Int = 3) {
        for effect in effects where banks[effect] == nil {
            guard let url = Bundle.main.url(forResource: effect.rawValue, withExtension: "wav") else {
                assertionFailure("Missing sound effect \(effect.rawValue).wav")
                continue
            }
            var bank: [AVAudioPlayer] = []
            for _ in 0..<copies {
                guard let player = try? AVAudioPlayer(contentsOf: url) else { continue }
                player.prepareToPlay()
                bank.append(player)
            }
            banks[effect] = bank
        }
    }

    /// Returns how long the effect runs, so a caller can sequence something after it.
    /// Silently does nothing and returns 0 if the asset is missing — a missing
    /// placeholder must never take the app down in front of a child.
    @discardableResult
    func play(_ effect: Effect, volumeScale: Float = 1.0) -> TimeInterval {
        guard let bank = banks[effect], !bank.isEmpty else { return 0 }
        let player = bank.first(where: { !$0.isPlaying }) ?? bank[0]
        player.volume = effectsVolume * volumeScale
        player.currentTime = 0
        player.play()
        return player.duration
    }

    /// Picks a giggle at random. The owl is a toy, not a sample player.
    @discardableResult
    func playGiggle(volumeScale: Float = 1.0) -> TimeInterval {
        guard let effect = Effect.giggles.randomElement() else { return 0 }
        return play(effect, volumeScale: volumeScale)
    }

    // MARK: Loops

    /// Starts an endless loop, fading in so it never arrives as a sudden noise.
    func startLoop(_ effect: Effect, volumeScale: Float = 1.0, fadeIn: TimeInterval = 0.25) {
        guard loops[effect] == nil,
              let url = Bundle.main.url(forResource: effect.rawValue, withExtension: "wav"),
              let player = try? AVAudioPlayer(contentsOf: url) else { return }

        loopScale = volumeScale
        player.numberOfLoops = -1
        player.volume = 0
        player.prepareToPlay()
        player.play()
        player.setVolume(effectsVolume * volumeScale, fadeDuration: fadeIn)
        loops[effect] = player
    }

    func stopLoop(_ effect: Effect, fadeOut: TimeInterval = 0.25) {
        guard let player = loops.removeValue(forKey: effect) else { return }
        player.setVolume(0, fadeDuration: fadeOut)
        // Keep the player alive for the length of the fade, then let it go.
        DispatchQueue.main.asyncAfter(deadline: .now() + fadeOut) {
            player.stop()
        }
    }

    func stopAllLoops() {
        loops.keys.forEach { stopLoop($0, fadeOut: 0.12) }
    }
}
