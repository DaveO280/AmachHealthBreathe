import AVFoundation
import Combine
import AmachBreatheShared

/// Plays a rising tone during inhale and falling tone during exhale.
/// Uses AVAudioEngine + AVAudioPlayerNode with a short sine-wave buffer.
@MainActor
public final class AudioPacer {

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var cancellable: AnyCancellable?
    private var lastBreathPhase: BreathPhase?
    private var isEngineRunning = false

    private let sampleRate: Double = 44100
    private let inhaleFreq: Float = 528    // Hz — rising tone
    private let exhaleFreq: Float = 396    // Hz — falling tone
    private let toneDuration: TimeInterval = 0.15

    public init(timer: MasterPhaseTimer) {
        setupEngine()
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

    // MARK: - Private

    private func setupEngine() {
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: nil)
        do {
            try engine.start()
            isEngineRunning = true
        } catch {
            // Audio unavailable — pacer degrades gracefully to silent
        }
    }

    private func handleState(_ state: PacerState) {
        guard state.sessionPhase.isActive, isEngineRunning else { return }

        let phase = state.breathPhase
        guard phase != lastBreathPhase else { return }
        lastBreathPhase = phase

        let freq: Float = phase == .inhale ? inhaleFreq : exhaleFreq
        playTone(frequency: freq)
    }

    private func playTone(frequency: Float) {
        let frameCount = AVAudioFrameCount(sampleRate * toneDuration)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount

        let data = buffer.floatChannelData![0]
        let omega = 2.0 * Float.pi * frequency / Float(sampleRate)
        for i in 0 ..< Int(frameCount) {
            // Linear fade-in/out envelope to avoid clicks
            let env = envelope(i: i, total: Int(frameCount))
            data[i] = env * sin(omega * Float(i)) * 0.3
        }

        playerNode.scheduleBuffer(buffer, completionHandler: nil)
        if !playerNode.isPlaying { playerNode.play() }
    }

    private func envelope(i: Int, total: Int) -> Float {
        let fadeLen = min(total / 10, 441)  // ~10 ms
        if i < fadeLen { return Float(i) / Float(fadeLen) }
        if i > total - fadeLen { return Float(total - i) / Float(fadeLen) }
        return 1.0
    }
}
