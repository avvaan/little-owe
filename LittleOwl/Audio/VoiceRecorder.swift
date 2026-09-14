import AVFoundation

/// Captures the child's voice into memory, and decides on its own when they have
/// finished talking.
///
/// **The recording never leaves memory and never touches disk.** There is no file, no
/// URL, no temporary directory. The captured audio exists as one `AVAudioPCMBuffer`
/// that is released the moment playback ends or anything is cancelled. That is the
/// whole privacy story of Echo mode, and it is a structural property of this type
/// rather than a policy someone has to remember.
final class VoiceRecorder {

    // MARK: Types

    struct Recording {
        let buffer: AVAudioPCMBuffer
        let duration: TimeInterval
    }

    enum StopReason {
        /// The child stopped talking. The normal ending.
        case silence
        /// The child is still going and hit the cap.
        case maxDuration
        /// Nothing loud enough ever arrived.
        case noSpeech
        /// The child tapped the owl again, or something else took over.
        case cancelled
        /// The engine could not start, or the system took the audio away.
        case failed
    }

    /// Smoothed 0...1 input level, on the main queue. Drives nothing today; Prayers and
    /// Word games use it to show the owl reacting while it listens.
    var onLevel: ((Float) -> Void)?

    /// Always delivered on the main queue. `recording` is nil for every reason except
    /// `.silence` and `.maxDuration` — and, deliberately, whenever `retainsAudio` is off.
    var onFinished: ((Recording?, StopReason) -> Void)?

    /// Every captured buffer, live, on the engine's own tap queue. Nothing here is kept
    /// by the recorder; it exists so on-device recognition can see the audio as it
    /// arrives without a second `AVAudioEngine` fighting for the same input node.
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?

    /// Whether the captured audio is kept so it can be played back.
    ///
    /// Echo needs it: replaying the child is the entire mode. Prayers does not — it only
    /// needs to know *that* the child spoke — so it turns this off and no buffer is ever
    /// copied or held at all. Turn-taking works exactly the same either way.
    var retainsAudio = true

    // MARK: Tuning
    //
    // These are turn-taking, not timeouts: the child stays in Echo when recording ends
    // and can tap again immediately. Nothing exits a mode on its own.

    /// How long the child may talk in one go.
    var maximumDuration: TimeInterval = 12

    /// Silence after speech that ends the turn.
    var silenceToFinish: TimeInterval = 1.1

    /// How long to wait for a child who tapped but has not said anything yet.
    var patienceBeforeSpeech: TimeInterval = 6

    /// Opening window used only to measure the room. Nothing counts as speech during
    /// it, so a television or a fan sets the bar instead of tripping it.
    var settleDuration: TimeInterval = 0.30

    private(set) var isRecording = false

    // MARK: Internals

    private let engine = AVAudioEngine()
    private var format: AVAudioFormat?

    /// Tap callbacks arrive on the engine's own queue while `stop` runs on the main
    /// queue, so everything the two of them share is behind this lock. `isCapturing`
    /// is part of that state: `removeTap` does not rule out a callback already in
    /// flight, and a late buffer must not land in a recording that has been assembled.
    private let stateLock = NSLock()
    private var isCapturing = false
    private var captured: [AVAudioPCMBuffer] = []

    private var elapsed: TimeInterval = 0
    private var silenceRun: TimeInterval = 0
    private var heardSpeech = false
    private var framesBeforeSpeech: AVAudioFrameCount = 0

    /// Exponentially-tracked noise floor, so a noisy room raises the bar instead of
    /// the owl listening forever.
    private var noiseFloor: Float = 0.004
    private var smoothedLevel: Float = 0

    // MARK: Control

    func start() {
        guard !isRecording else { return }
        reset()

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)

        // A zero sample rate means the session has not given us an input yet.
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            finish(nil, .failed)
            return
        }
        format = inputFormat

        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.consume(buffer)
        }

        do {
            engine.prepare()
            try engine.start()
            isRecording = true
            stateLock.lock()
            isCapturing = true
            stateLock.unlock()
        } catch {
            input.removeTap(onBus: 0)
            finish(nil, .failed)
        }
    }

    func stop(reason: StopReason = .cancelled) {
        guard isRecording else { return }
        teardown()

        switch reason {
        case .silence, .maxDuration:
            finish(retainsAudio ? assembleRecording() : nil, reason)
        default:
            stateLock.lock()
            captured.removeAll()
            stateLock.unlock()
            finish(nil, reason)
        }
    }

    // MARK: Capture

    /// Runs on the engine's tap queue.
    private func consume(_ buffer: AVAudioPCMBuffer) {
        let level = buffer.meanSquareLevel()
        let frames = buffer.frameLength
        let seconds = Double(frames) / buffer.format.sampleRate

        stateLock.lock()
        let capturing = isCapturing
        stateLock.unlock()
        guard capturing else { return }

        // Outside the lock: a consumer of live audio must never be able to deadlock the
        // tap against the main queue.
        onBuffer?(buffer)

        // The tap hands out a buffer it reuses immediately, so anything kept has to be
        // copied. When nothing is kept, nothing is copied either.
        let copy: AVAudioPCMBuffer?
        if retainsAudio {
            guard let made = buffer.copied() else { return }
            copy = made
        } else {
            copy = nil
        }

        stateLock.lock()
        guard isCapturing else {
            stateLock.unlock()
            return
        }

        elapsed += seconds

        // Speech is a decent multiple above the room. See
        // `tools/simulate_turn_detection.py` for where these numbers come from — every
        // one of them fixes a case that misbehaved.
        let settling = elapsed <= settleDuration
        var threshold = max(noiseFloor * 3.5, 0.012)
        if heardSpeech {
            // Hysteresis: once the child is talking, the bar to *stay* talking is
            // lower, so the dips between syllables do not read as the end of the turn.
            threshold *= 0.55
        }
        let isSpeech = !settling && level > threshold

        if settling {
            // Measuring the room: track it quickly in both directions.
            noiseFloor += (level - noiseFloor) * 0.30
        } else if !isSpeech {
            // Adapt to noise, never to speech. Letting the floor climb during speech
            // walks the threshold up past the child's own voice and ends the turn
            // while they are still talking.
            noiseFloor += (level - noiseFloor) * (level < noiseFloor ? 0.25 : 0.002)
        }

        if let copy { captured.append(copy) }

        if isSpeech {
            heardSpeech = true
            silenceRun = 0
        } else {
            silenceRun += seconds
            if !heardSpeech {
                framesBeforeSpeech += frames
            }
        }

        // Asymmetric smoothing: opens fast, closes slowly. Used for display only.
        let target = VoiceRecorder.normalise(level)
        smoothedLevel += (target - smoothedLevel) * (target > smoothedLevel ? 0.5 : 0.18)
        let reported = smoothedLevel

        let reason: StopReason?
        if elapsed >= maximumDuration {
            reason = .maxDuration
        } else if heardSpeech, silenceRun >= silenceToFinish {
            reason = .silence
        } else if !heardSpeech, elapsed >= patienceBeforeSpeech {
            reason = .noSpeech
        } else {
            reason = nil
        }

        stateLock.unlock()

        DispatchQueue.main.async { [weak self] in
            self?.onLevel?(reported)
            if let reason { self?.stop(reason: reason) }
        }
    }

    /// Joins the captured buffers into one, dropping the silence before the child
    /// started talking so the owl answers promptly. Call only after `teardown`.
    private func assembleRecording() -> Recording? {
        stateLock.lock()
        defer {
            captured.removeAll()
            stateLock.unlock()
        }

        guard let format, !captured.isEmpty else { return nil }

        let total = captured.reduce(AVAudioFrameCount(0)) { $0 + $1.frameLength }
        let lead = min(framesBeforeSpeech, total)
        let wanted = total - lead
        guard wanted > 0,
              let joined = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: wanted) else { return nil }

        var skipped: AVAudioFrameCount = 0
        for buffer in captured {
            if skipped < lead {
                let skipping = min(buffer.frameLength, lead - skipped)
                skipped += skipping
                if skipping == buffer.frameLength { continue }
                joined.append(buffer, fromFrame: skipping)
            } else {
                joined.append(buffer, fromFrame: 0)
            }
        }

        guard joined.frameLength > 0 else { return nil }
        return Recording(
            buffer: joined,
            duration: Double(joined.frameLength) / format.sampleRate
        )
    }

    // MARK: Lifecycle

    private func reset() {
        stateLock.lock()
        captured.removeAll()
        stateLock.unlock()

        elapsed = 0
        silenceRun = 0
        heardSpeech = false
        framesBeforeSpeech = 0
        noiseFloor = 0.004
        smoothedLevel = 0
    }

    private func teardown() {
        isRecording = false

        // Close the gate before removing the tap: `removeTap` does not wait for a
        // callback that has already started.
        stateLock.lock()
        isCapturing = false
        stateLock.unlock()

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    private func finish(_ recording: Recording?, _ reason: StopReason) {
        DispatchQueue.main.async { [weak self] in
            self?.onFinished?(recording, reason)
        }
    }

    /// Maps a linear RMS to 0...1 across roughly −45 dB to −12 dB, which is where
    /// a child's voice at arm's length from an iPad sits.
    static func normalise(_ level: Float) -> Float {
        guard level > 0 else { return 0 }
        let decibels = 20 * log10(level)
        return min(max((decibels + 45) / 33, 0), 1)
    }
}

// MARK: - Buffer helpers

extension AVAudioPCMBuffer {

    /// The tap hands out a buffer it reuses immediately, so anything kept has to be copied.
    func copied() -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameLength),
              let source = floatChannelData,
              let destination = copy.floatChannelData else { return nil }

        let channels = Int(format.channelCount)
        let frames = Int(frameLength)
        for channel in 0..<channels {
            destination[channel].update(from: source[channel], count: frames)
        }
        copy.frameLength = frameLength
        return copy
    }

    /// Appends `other` from `fromFrame` onwards, up to this buffer's capacity.
    func append(_ other: AVAudioPCMBuffer, fromFrame offset: AVAudioFrameCount) {
        guard offset < other.frameLength,
              let source = other.floatChannelData,
              let destination = floatChannelData else { return }

        let available = frameCapacity - frameLength
        let frames = min(other.frameLength - offset, available)
        guard frames > 0 else { return }

        let channels = Int(min(format.channelCount, other.format.channelCount))
        for channel in 0..<channels {
            destination[channel]
                .advanced(by: Int(frameLength))
                .update(from: source[channel].advanced(by: Int(offset)), count: Int(frames))
        }
        frameLength += frames
    }

    /// Root-mean-square across the first channel.
    func meanSquareLevel() -> Float {
        guard let data = floatChannelData, frameLength > 0 else { return 0 }
        let samples = data[0]
        var sum: Float = 0
        for index in 0..<Int(frameLength) {
            let value = samples[index]
            sum += value * value
        }
        return (sum / Float(frameLength)).squareRoot()
    }
}
