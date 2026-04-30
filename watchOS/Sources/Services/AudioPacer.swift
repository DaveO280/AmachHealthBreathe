import AVFoundation
import Combine
import AmachBreatheShared

/// Continuous-tone breath pacer. Pink noise driven through a swept bandpass
/// filter — center frequency rides 200 → 800 Hz over each inhale and back
/// 800 → 200 Hz over each exhale, driven by the breathProgress published by
/// MasterPhaseTimer. The filter sweep is gapless across phase boundaries
/// (the boundary frequency matches on both sides), and a per-phase volume
/// envelope (gentle fade-in / sustain / soft fade-out) gives an organic
/// breath-pulse feel without electronic clicks.
@MainActor
public final class AudioPacer {

    /// State touched only by the audio render thread. Marked `@unchecked
    /// Sendable` because the render block is the sole accessor.
    private final class RenderState: @unchecked Sendable {
        // Paul Kellet pink-noise filter
        var pb0: Float = 0
        var pb1: Float = 0
        var pb2: Float = 0
        var pb3: Float = 0
        var pb4: Float = 0
        var pb5: Float = 0
        var pb6: Float = 0
        // Xorshift32 RNG state
        var rng: UInt32 = 0xCAFE_BABE
        // Chamberlin state-variable filter
        var smoothedCenter: Float = 200
        var lp: Float = 0
        var bp: Float = 0
        // Master amplitude smoothing
        var smoothedAmp: Float = 0
    }

    /// Cross-thread knobs written by MainActor and read by the audio thread.
    /// Each knob is a single aligned 32-bit Float, naturally atomic on the
    /// supported Apple architectures; the audio thread reads each once per
    /// render call (not per sample), so torn reads are not a concern.
    private final class Knobs: @unchecked Sendable {
        var targetCenter: Float = 200
        var targetAmp: Float = 0
    }

    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private var cancellable: AnyCancellable?
    private var isEngineRunning = false

    private let sampleRate: Double = 22_050
    private let centerLow: Float = 200
    private let centerHigh: Float = 800
    private let filterQ: Float = 4
    private let gain: Float = 0.18

    private let renderState = RenderState()
    private let knobs = Knobs()

    public init(timer: MasterPhaseTimer) {
        knobs.targetCenter = centerLow
        configureAudioSession()
        setupEngine()
        cancellable = timer.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                self?.handleState(state)
            }
    }

    public func stop() {
        cancellable = nil
        knobs.targetAmp = 0
        // Let the smoothed amplitude ramp to zero (~50 ms) before tearing the
        // engine down, so the user never hears an abrupt cutoff.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard let self, self.isEngineRunning else { return }
            self.engine.stop()
            self.isEngineRunning = false
        }
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
        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate, channels: 1) else { return }

        // Capture only Sendable values into the render block. `RenderState`
        // and `Knobs` are @unchecked Sendable; primitives are too.
        let state = renderState
        let cross = knobs
        let sr = sampleRate
        let toneGain = gain
        let q: Float = 1.0 / filterQ
        // One-pole exponential smoothing, ~10 ms time constant.
        let smoothAlpha = Float(1.0 - exp(-1.0 / (sr * 0.010)))
        let piOverSr = Float(Double.pi / sr)
        let kellettScale: Float = 0.11

        let node = AVAudioSourceNode(format: format) {
            _, _, frameCount, audioBufferList -> OSStatus in

            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let centerTarget = cross.targetCenter
            let ampTarget = cross.targetAmp

            for buffer in abl {
                guard let raw = buffer.mData else { continue }
                let ptr = raw.assumingMemoryBound(to: Float.self)

                for i in 0 ..< Int(frameCount) {
                    // --- White noise via xorshift32 ---
                    var r = state.rng
                    r ^= r << 13
                    r ^= r >> 17
                    r ^= r << 5
                    state.rng = r
                    let white = Float(Int32(bitPattern: r)) / Float(Int32.max)

                    // --- Pink-noise shaping (Paul Kellet) ---
                    state.pb0 = 0.99886 * state.pb0 + white * 0.0555179
                    state.pb1 = 0.99332 * state.pb1 + white * 0.0750759
                    state.pb2 = 0.96900 * state.pb2 + white * 0.1538520
                    state.pb3 = 0.86650 * state.pb3 + white * 0.3104856
                    state.pb4 = 0.55000 * state.pb4 + white * 0.5329522
                    state.pb5 = -0.7616  * state.pb5 - white * 0.0168980
                    let pink = (state.pb0 + state.pb1 + state.pb2 + state.pb3
                              + state.pb4 + state.pb5 + state.pb6
                              + white * 0.5362) * kellettScale
                    state.pb6 = white * 0.115926

                    // --- Smooth filter center; recompute SVF coefficient ---
                    state.smoothedCenter += (centerTarget - state.smoothedCenter) * smoothAlpha
                    let f = 2.0 * sin(piOverSr * state.smoothedCenter)

                    // --- Chamberlin SVF (bandpass tap) ---
                    let high = pink - state.lp - q * state.bp
                    state.bp += f * high
                    state.lp += f * state.bp

                    // --- Master amplitude smoothing ---
                    state.smoothedAmp += (ampTarget - state.smoothedAmp) * smoothAlpha

                    ptr[i] = state.bp * toneGain * state.smoothedAmp
                }
            }
            return noErr
        }
        sourceNode = node

        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)

        do {
            try engine.start()
            isEngineRunning = true
        } catch {
            isEngineRunning = false
        }
    }

    // MARK: - State (MainActor)

    private func handleState(_ state: PacerState) {
        guard isEngineRunning else { return }
        guard state.sessionPhase.isActive else {
            knobs.targetAmp = 0
            return
        }

        let p = Float(state.breathProgress)
        let center: Float
        switch state.breathPhase {
        case .inhale:
            center = centerLow + (centerHigh - centerLow) * p
        case .exhale:
            center = centerHigh - (centerHigh - centerLow) * p
        }
        knobs.targetCenter = center
        knobs.targetAmp = phaseEnvelope(progress: p)
    }

    /// Per-phase volume envelope: smoothstep fade-in over the first 12 % of
    /// the phase, full sustain through the middle, smoothstep fade-out over
    /// the last 12 %. Inhale's fade-out and the next exhale's fade-in (and
    /// vice-versa) align at phase boundaries — combined with a continuous
    /// filter sweep — to give a smooth breath-pulse feel.
    private func phaseEnvelope(progress: Float) -> Float {
        let fadeIn: Float = 0.12
        let fadeOut: Float = 0.12
        if progress < fadeIn {
            let t = progress / fadeIn
            return t * t * (3 - 2 * t)
        }
        if progress > 1 - fadeOut {
            let t = (1 - progress) / fadeOut
            return t * t * (3 - 2 * t)
        }
        return 1
    }
}
