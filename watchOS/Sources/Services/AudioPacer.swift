import AVFoundation
import Combine
import AmachBreatheShared

/// Soft-thump breath pacer. At each phase transition — inhale start and
/// exhale start — plays one short percussive sine burst whose pitch slides
/// 60 → 30 Hz over 180 ms while the gain decays exponentially to silence by
/// 350 ms. There is no audio between thumps; the haptic engine fires on the
/// same transitions, so thump and tap land together.
@MainActor
public final class AudioPacer {

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

    public init(timer: MasterPhaseTimer) {
        configureAudioSession()
        setupEngine()
        thumpBuffer = renderThumpBuffer()
        cancellable = timer.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                self?.handleState(state)
            }
    }

    public func stop() {
        cancellable = nil
        lastBreathPhase = nil
        if isEngineRunning {
            engine.stop()
            isEngineRunning = false
        }
    }

    /// Re-activate the AVAudioSession and restart the engine if needed.
    /// Call this right before a session/calibration begins. The session can
    /// be deactivated by the system between AudioPacer.init (at runner init,
    /// often app launch) and the actual moment audio needs to play, especially
    /// when an HKWorkoutSession then claims the audio route.
    public func prepare() {
        configureAudioSession()
        if !engine.isRunning {
            do {
                try engine.start()
                isEngineRunning = true
            } catch {
                isEngineRunning = false
            }
        } else {
            isEngineRunning = true
        }
        lastBreathPhase = nil
    }

    // MARK: - Setup

    private func configureAudioSession() {
        #if !os(macOS)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true, options: [])
        } catch {
            // Audio unavailable — pacer degrades gracefully to silent.
        }
        #endif
    }

    private func setupEngine() {
        engine.attach(playerNode)
        let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate, channels: 1)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        do {
            try engine.start()
            isEngineRunning = true
        } catch {
            // Audio unavailable — pacer degrades gracefully to silent.
        }
    }

    // MARK: - Buffer synthesis

    /// Render the thump once at init: a sine whose frequency falls
    /// geometrically from 60 Hz to 30 Hz across the first 180 ms (constant
    /// thereafter), shaped by an exponential gain envelope that's at the
    /// 0.5 attack at t = 0 and ≈ -40 dB by t = 350 ms.
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
        // Per-sample geometric multiplier that takes startFreq → endFreq in
        // exactly pitchRampFrames samples.
        let freqRatio = pow(endFreq / startFreq, 1.0 / Double(pitchRampFrames))
        // Envelope time constant: g(t) = attack * exp(-t/τ). Pick τ so that
        // by t = 350 ms the envelope is at attack/100 (~ -40 dB).
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

    // MARK: - State (MainActor)

    private func handleState(_ state: PacerState) {
        // Reset on inactive so the next active phase (e.g. the next
        // calibration rate after timer.stop/start) plays a thump on its
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
        // scheduleBuffer raises NSException if the engine has stopped or the
        // node was detached (e.g. simulator audio failures). Guard explicitly.
        guard engine.isRunning else { return }
        playerNode.scheduleBuffer(
            buffer, at: nil, options: [], completionHandler: nil)
        if !playerNode.isPlaying { playerNode.play() }
    }
}
