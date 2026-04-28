import AVFoundation
import Combine
import AmachBreatheShared

/// Plays rising/falling sine tones on breath phase transitions.
/// Mirrors the watchOS AudioPacer; adds iOS AVAudioSession category setup.
@MainActor
final class iPhoneAudioPacer {

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var cancellable: AnyCancellable?
    private var lastBreathPhase: BreathPhase?
    private var isEngineRunning = false

    private let sampleRate: Double = 44_100
    private let inhaleFreq: Float  = 528   // Hz
    private let exhaleFreq: Float  = 396   // Hz
    private let toneDuration: TimeInterval = 0.15

    init(timer: iPhoneMasterPhaseTimer) {
        configureAudioSession()
        setupEngine()
        cancellable = timer.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in self?.handleState(state) }
    }

    func stop() {
        cancellable = nil
        lastBreathPhase = nil
        if isEngineRunning { engine.stop(); isEngineRunning = false }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Private

    private func configureAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(
            .playback, mode: .default, options: .mixWithOthers)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func setupEngine() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: nil)
        do { try engine.start(); isEngineRunning = true } catch { }
    }

    private func handleState(_ state: PacerState) {
        guard state.sessionPhase.isActive, isEngineRunning else { return }
        let phase = state.breathPhase
        guard phase != lastBreathPhase else { return }
        lastBreathPhase = phase
        playTone(frequency: phase == .inhale ? inhaleFreq : exhaleFreq)
    }

    private func playTone(frequency: Float) {
        let frameCount = AVAudioFrameCount(sampleRate * toneDuration)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount
        let data  = buffer.floatChannelData![0]
        let omega = 2.0 * Float.pi * frequency / Float(sampleRate)
        let total = Int(frameCount)
        for i in 0 ..< total {
            let env = envelope(i: i, total: total)
            data[i] = env * sin(omega * Float(i)) * 0.3
        }
        player.scheduleBuffer(buffer, completionHandler: nil)
        if !player.isPlaying { player.play() }
    }

    private func envelope(i: Int, total: Int) -> Float {
        let fade = min(total / 10, 441)
        if i < fade      { return Float(i) / Float(fade) }
        if i > total - fade { return Float(total - i) / Float(fade) }
        return 1.0
    }
}
