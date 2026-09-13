import AVFoundation

/// Tiny sound-effect bank.
///
/// Deliberately `AVAudioPlayer` rather than `SKAction.playSoundFileNamed`: the UX
/// rules require a *soft* palette with a single volume the parent can trim, and
/// `SKAction` sounds cannot be attenuated. When Echo mode brings in `AVAudioEngine`
/// the session category changes, but these players keep working unchanged.
final class SoundKit {

    static let shared = SoundKit()
    private init() {}

    /// Effect bed sits well under the owl's voice. Parent settings will drive this later.
    var effectsVolume: Float = 0.55

    private var banks: [String: [AVAudioPlayer]] = [:]

    /// Category is `.playback` for now. Echo mode will switch this to
    /// `.playAndRecord`; it is called out here so the change is easy to find.
    func configureSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [])
        try? session.setActive(true, options: [])
    }

    /// `copies` lets the same effect overlap itself when a child taps quickly.
    func preload(_ names: [String], copies: Int = 3) {
        for name in names where banks[name] == nil {
            guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else {
                assertionFailure("Missing sound effect \(name).wav")
                continue
            }
            var bank: [AVAudioPlayer] = []
            for _ in 0..<copies {
                guard let player = try? AVAudioPlayer(contentsOf: url) else { continue }
                player.prepareToPlay()
                bank.append(player)
            }
            banks[name] = bank
        }
    }

    /// Silently does nothing if the effect is missing — a missing placeholder asset
    /// must never take the app down in front of a child.
    func play(_ effect: Effect, volumeScale: Float = 1.0) {
        guard let bank = banks[effect.rawValue], !bank.isEmpty else { return }
        let player = bank.first(where: { !$0.isPlaying }) ?? bank[0]
        player.volume = effectsVolume * volumeScale
        player.currentTime = 0
        player.play()
    }

    enum Effect: String, CaseIterable {
        case tap  = "tap_soft"
        case hop  = "hop"
        case wake = "wake"
    }
}
