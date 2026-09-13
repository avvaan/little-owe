import AVFoundation

/// Thin wrapper over the iOS 17 microphone permission API.
///
/// The prompt appears on the **first tap of the owl** and never before: not at launch,
/// not on a splash screen, not behind a "continue" button a child would have to read.
/// The parent-facing explanation lives in `NSMicrophoneUsageDescription`.
enum MicrophonePermission {

    enum Status {
        case undetermined
        case granted
        case denied
    }

    static var status: Status {
        switch AVAudioApplication.shared.recordPermission {
        case .undetermined: return .undetermined
        case .granted:      return .granted
        case .denied:       return .denied
        @unknown default:   return .denied
        }
    }

    /// Completion is always delivered on the main queue.
    static func request(_ completion: @escaping (Bool) -> Void) {
        AVAudioApplication.requestRecordPermission { granted in
            DispatchQueue.main.async { completion(granted) }
        }
    }
}
