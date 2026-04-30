import AVFoundation
import Combine
import AmachBreatheShared

/// Continuous pitch-shift breathing pacer.
///
/// Synthesises a single, gapless sine tone whose pitch ramps with the breath:
/// 110 Hz → 220 Hz across the inhale, 220 Hz → 110 Hz across the exhale. The
/// tone passes through a one-pole low-pass at ~700 Hz to soften timbre and
/// damp any micro-clicks from parameter steps. Output is muted whenever the
/// session phase is not active.
@MainActor
public final class AudioPacer {

    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode!

    private var cancellable: AnyCancellable?
    private var isEngineRunning = false

    private let sampleRate: Double = 44_100
    private let minFreq: Double = 110
    private let maxFreq: Double = 220
    private let outputGain: Float = 0.22
    private let lowPassCutoff: Double = 700

    // Pre-computed one-pole low-pass coefficient: alpha = 1 - exp(-2π·fc/fs)
    private let lowPassAlpha: Double

    // Cross-thread parameters: written on main, read on the audio render
    // thread. Aligned 8-byte loads/stores are atomic on aarch64; the in-render
    // ramp masks any sample-level step.
    private var targetFrequency: Double = 110
    private var targetGain: Double = 0

    // Render-thread-only state.
    private var phase: Double = 0
    private var lastRenderedFrequency: Double = 110
    private var lastRenderedGain: Double = 0
    private var lowPassState: Double = 0

    public init(timer: MasterPhaseTimer) {
        self.lowPassAlpha = 1.0 - exp(-2.0 * Double.pi * lowPassCutoff / sampleRate)
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
        targetGain = 0
        if isEngineRunning {
            engine.stop()
            isEngineRunning = false
        }
        try? AVAudioSession.sharedInstance().setActive(
            false, options: [.notifyOthersOnDeactivation])
    }

    // MARK: - Setup

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            // Audio unavailable — pacer degrades silently.
        }
    }

    private func setupEngine() {
        let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate, channels: 1)!

        sourceNode = AVAudioSourceNode(format: format) {
            [weak self] _, _, frameCount, audioBufferList in
            guard let self else { return noErr }
            return self.render(
                frameCount: frameCount, audioBufferList: audioBufferList)
        }

        engine.attach(sourceNode)
        engine.connect(sourceNode, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = outputGain

        do {
            try engine.start()
            isEngineRunning = true
        } catch {
            // Audio unavailable — pacer degrades silently.
        }
    }

    // MARK: - Render (audio thread)

    private func render(
        frameCount: AVAudioFrameCount,
        audioBufferList: UnsafeMutablePointer<AudioBufferList>
    ) -> OSStatus {
        let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
        let frames = Int(frameCount)
        let twoPi = 2.0 * Double.pi

        let startFreq = lastRenderedFrequency
        let endFreq = targetFrequency
        let startGain = lastRenderedGain
        let endGain = targetGain
        let invDenom = frames > 1 ? 1.0 / Double(frames - 1) : 1.0

        var localPhase = phase
        var lp = lowPassState
        let alpha = lowPassAlpha

        for buffer in abl {
            guard let raw = buffer.mData else { continue }
            let ptr = raw.assumingMemoryBound(to: Float.self)
            for i in 0..<frames {
                let t = frames > 1 ? Double(i) * invDenom : 1.0
                let f = startFreq + (endFreq - startFreq) * t
                let g = startGain + (endGain - startGain) * t
                let raw = sin(localPhase) * g
                lp += alpha * (raw - lp)
                ptr[i] = Float(lp)
                localPhase += twoPi * f / sampleRate
                if localPhase >= twoPi { localPhase -= twoPi }
            }
        }

        phase = localPhase
        lowPassState = lp
        lastRenderedFrequency = endFreq
        lastRenderedGain = endGain
        return noErr
    }

    // MARK: - State updates (main thread)

    private func handleState(_ state: PacerState) {
        guard isEngineRunning else { return }

        guard state.sessionPhase.isActive else {
            targetGain = 0
            return
        }

        let progress = max(0.0, min(1.0, state.breathProgress))
        let span = maxFreq - minFreq
        switch state.breathPhase {
        case .inhale:
            targetFrequency = minFreq + span * progress
        case .exhale:
            targetFrequency = maxFreq - span * progress
        }
        targetGain = 1.0
    }
}
