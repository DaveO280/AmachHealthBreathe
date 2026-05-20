import AVFoundation
import AmachBreatheShared

@MainActor
final class iPhoneAudioBreathTracker: ObservableObject {

    enum Status: Equatable {
        case off
        case requestingPermission
        case denied
        case listening
        case unavailable
    }

    @Published private(set) var status: Status = .off

    private let engine = AVAudioEngine()
    private var analyzer: AudioBreathEnvelopeAnalyzer?
    private var sessionStart: Date?
    private var isAnalysisActive = false
    private var shouldRun = false
    private var permissionGranted = false
    private var targetBPM: Double = 0

    /// Mirrors `isAnalysisActive` / `sessionStart` for the realtime audio tap (audio thread).
    private let tapStateLock = NSLock()
    private nonisolated(unsafe) var tapAnalysisActive = false
    private nonisolated(unsafe) var tapSessionStart: Date?
    private nonisolated(unsafe) var tapAnalyzer: AudioBreathEnvelopeAnalyzer?

    func start(targetBPM: Double) async {
        stop()
        shouldRun = true
        self.targetBPM = targetBPM
        let newAnalyzer = AudioBreathEnvelopeAnalyzer(targetBPM: targetBPM)
        self.analyzer = newAnalyzer
        tapStateLock.lock()
        tapAnalyzer = newAnalyzer
        tapStateLock.unlock()
        status = .requestingPermission

        let granted = await requestMicrophonePermission()
        guard shouldRun else { return }
        permissionGranted = granted
        guard granted else {
            cleanupEngine()
            analyzer = nil
            clearTapState()
            shouldRun = false
            status = .denied
            return
        }

        do {
            try configureAudioSession()
            try startEngine()
            sessionStart = Date()
            syncTapState()
            status = .listening
        } catch {
            status = .unavailable
            cleanupEngine()
            analyzer = nil
            clearTapState()
            shouldRun = false
        }
    }

    func setAnalysisActive(_ active: Bool) {
        isAnalysisActive = active
        syncTapState()
    }

    func finishMetrics() -> AudioBreathMetrics? {
        guard let analyzer else {
            return nil
        }
        let metrics = analyzer.metrics(permissionGranted: permissionGranted)
        stop()
        return metrics
    }

    func stop() {
        cleanupEngine()
        analyzer = nil
        sessionStart = nil
        isAnalysisActive = false
        shouldRun = false
        permissionGranted = false
        targetBPM = 0
        status = .off
        clearTapState()
    }

    // MARK: - Permission

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    // MARK: - Audio

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .measurement,
            options: [.mixWithOthers, .defaultToSpeaker]
        )
        try session.setActive(true, options: [])
    }

    private func startEngine() throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else {
            throw AudioTrackerError.invalidInputFormat
        }

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2_048, format: format) { [weak self] buffer, _ in
            self?.handle(buffer: buffer)
        }

        engine.prepare()
        try engine.start()
    }

    nonisolated private func handle(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }

        tapStateLock.lock()
        let active = tapAnalysisActive
        let start = tapSessionStart
        let analyzer = tapAnalyzer
        tapStateLock.unlock()
        guard active, let start, let analyzer else { return }

        let channelCount = max(1, Int(buffer.format.channelCount))
        var sumSquares: Double = 0
        var sampleCount = 0

        for channel in 0..<channelCount {
            let samples = channelData[channel]
            for frame in 0..<frameLength {
                let value = Double(samples[frame])
                sumSquares += value * value
                sampleCount += 1
            }
        }

        guard sampleCount > 0 else { return }
        let rms = sqrt(sumSquares / Double(sampleCount))
        let amplitude = min(1, rms * 8)
        let elapsed = Date().timeIntervalSince(start)
        analyzer.addAmplitude(amplitude, elapsed: elapsed)
    }

    private func syncTapState() {
        tapStateLock.lock()
        tapAnalysisActive = isAnalysisActive
        tapSessionStart = sessionStart
        tapAnalyzer = analyzer
        tapStateLock.unlock()
    }

    private func clearTapState() {
        tapStateLock.lock()
        tapAnalysisActive = false
        tapSessionStart = nil
        tapAnalyzer = nil
        tapStateLock.unlock()
    }

    private func cleanupEngine() {
        if engine.inputNode.numberOfInputs > 0 {
            engine.inputNode.removeTap(onBus: 0)
        }
        if engine.isRunning {
            engine.stop()
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

private enum AudioTrackerError: Error {
    case invalidInputFormat
}
