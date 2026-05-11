import XCTest
@testable import AmachBreatheShared

final class AudioBreathEnvelopeAnalyzerTests: XCTestCase {

    func testMetricsEstimateTargetBreathingRateFromPeriodicEnvelope() {
        let samples = makeEnvelopeSamples(
            targetBPM: 6.0,
            duration: 120,
            sampleRate: 10,
            noise: 0.01
        )

        let metrics = AudioBreathEnvelopeAnalyzer.metrics(
            targetBPM: 6.0,
            samples: samples
        )

        XCTAssertEqual(metrics.dataQuality, .good)
        XCTAssertEqual(metrics.estimatedBreathingBPM ?? 0, 6.0, accuracy: 0.5)
        XCTAssertGreaterThan(metrics.adherenceScore ?? 0, 0.85)
        XCTAssertGreaterThan(metrics.confidence, 0.6)
        XCTAssertFalse(metrics.permissionGranted == false)
    }

    func testMetricsHandlesHalfCycleLikePeaksConservatively() {
        let samples = makeEnvelopeSamples(
            targetBPM: 6.0,
            duration: 120,
            sampleRate: 10,
            periodMultiplier: 0.5,
            noise: 0.01
        )

        let metrics = AudioBreathEnvelopeAnalyzer.metrics(
            targetBPM: 6.0,
            samples: samples
        )

        XCTAssertEqual(metrics.estimatedBreathingBPM ?? 0, 6.0, accuracy: 0.6)
        XCTAssertGreaterThan(metrics.adherenceScore ?? 0, 0.8)
        XCTAssertGreaterThan(metrics.detectedPeakCount, 8)
        XCTAssertLessThan(metrics.confidence, 0.9)
    }

    func testMetricsReturnsLowQualityForFlatSignal() {
        let samples = stride(from: 0.0, through: 60.0, by: 0.1).map {
            AudioBreathEnvelopeAnalyzer.Sample(elapsed: $0, amplitude: 0.02)
        }

        let metrics = AudioBreathEnvelopeAnalyzer.metrics(
            targetBPM: 6.0,
            samples: samples
        )

        XCTAssertEqual(metrics.dataQuality, .low)
        XCTAssertNil(metrics.estimatedBreathingBPM)
        XCTAssertLessThan(metrics.confidence, 0.2)
    }

    func testMetricsHandlesDeniedPermission() {
        let metrics = AudioBreathEnvelopeAnalyzer.metrics(
            targetBPM: 6.0,
            samples: [],
            permissionGranted: false
        )

        XCTAssertEqual(metrics.dataQuality, .unavailable)
        XCTAssertFalse(metrics.permissionGranted)
        XCTAssertNil(metrics.estimatedBreathingBPM)
    }

    private func makeEnvelopeSamples(
        targetBPM: Double,
        duration: TimeInterval,
        sampleRate: Double,
        periodMultiplier: Double = 1.0,
        noise: Double = 0
    ) -> [AudioBreathEnvelopeAnalyzer.Sample] {
        let targetPeriod = 60.0 / targetBPM
        let signalPeriod = targetPeriod * periodMultiplier
        let step = 1.0 / sampleRate

        return stride(from: 0.0, through: duration, by: step).map { elapsed in
            let wave = (sin((elapsed / signalPeriod) * 2 * Double.pi - Double.pi / 2) + 1) / 2
            let amplitude = 0.02 + (wave * 0.18) + noise
            return AudioBreathEnvelopeAnalyzer.Sample(elapsed: elapsed, amplitude: amplitude)
        }
    }
}
