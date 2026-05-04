import AVFoundation
import Combine
import AmachBreatheShared

/// Soft-thump breath pacer for iOS. Mirrors watchOS `AudioPacer`: a single
/// short percussive sine burst on every breath transition (inhale start /
/// exhale start). The pitch slides 60 → 30 Hz over the first 180 ms while the
/// gain decays exponentially toward silence by ~350 ms. Silence in between.
@MainActor
final class iPhoneAudioPacer {

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var cancellable: AnyCancellable?
    private var lastBreathPhase: BreathPhase?
    private var isEngineRunning = false
    private var thumpBuffer: AVAudioPCMBuffer?

    private let sampleRate: Double = 22_050
    private let startFreq: Double = 60
    private let endFreq: Double = 30
    private let pitchRampDuration: TimeInterval = 0.180
    private let totalDuration: TimeInterval = 0.400
    private let attackGain: Float = 0.5

    init(timer: iPhoneMasterPhaseTimer) {
        configureAudioSession()
        setupEngine()
        thumpBuffer = renderThumpBuffer()
        cancellable = timer.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in self?.handleState(state) }
    }

    func stop() {
        cancellable = nil
        lastBreathPhase = nil
        if isEngineRunning {
            engine.stop()
            isEngineRunning = false
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Setup

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true, options: [])
        } catch {
            // Audio unavailable — pacer degrades gracefully to silent.
        }
    }

    private func setupEngine() {
        engine.attach(playerNode)
        // Connect with an explicit mono format. Passing nil here can raise an
        // exception when the player node has no scheduled audio yet, because
        // the engine cannot infer the format on iOS.
        let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate, channels: 1)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        do {
            try engine.start()
            isEngineRunning = true
        } catch {
            isEngineRunning = false
        }
    }

    // MARK: - Buffer synthesis

    /// Render the thump once: a sine whose frequency falls geometrically from
    /// 60 Hz to 30 Hz across the first 180 ms (constant thereafter), shaped by
    /// an exponential gain envelope at attack/2 at t = 0 and ≈ -40 dB by
    /// t = 350 ms.
    private func renderThumpBuffer() -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate, channels: 1) else { return nil }

        let frameCount = AVAudioFrameCount(sampleRate * totalDuration)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount

        guard let data = buffer.floatChannelData?[0] else { return nil }

        let sr = sampleRate
        let pitchRampFrames = Int(sr * pitchRampDuration)
        let freqRatio = pow(endFreq / startFreq, 1.0 / Double(pitchRampFrames))
        let tau = 0.350 / log(100.0)
        let twoPi = 2.0 * Double.pi

        var phase: Double = 0
        var freq = startFreq

        for i in 0 ..< Int(frameCount) {
            let t = Double(i) / sr
            let env = Float(Double(attackGain) * exp(-t / tau))
            data[i] = Float(sin(phase)) * env

            phase += twoPi * freq / sr
            if phase > twoPi { phase -= twoPi }
            if i < pitchRampFrames {
                freq *= freqRatio
            }
        }
        return buffer
    }

    // MARK: - State

    private func handleState(_ state: PacerState) {
        // Reset on inactive so the next active phase plays a thump on its
        // first inhale even if it matches the last seen breath phase.
        guard state.sessionPhase.isActive else {
            lastBreathPhase = nil
            return
        }
        guard isEngineRunning else { return }
        let breath = state.breathPhase
        guard breath != lastBreathPhase else { return }
        lastBreathPhase = breath
        playThump()
    }

    private func playThump() {
        guard let buffer = thumpBuffer else { return }
        guard engine.isRunning else { return }
        playerNode.scheduleBuffer(
            buffer, at: nil, options: [], completionHandler: nil)
        if !playerNode.isPlaying { playerNode.play() }
    }
}
