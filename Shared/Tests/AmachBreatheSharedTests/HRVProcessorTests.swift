import XCTest
@testable import AmachBreatheShared

final class HRVProcessorTests: XCTestCase {

    // MARK: - RMSSD accuracy

    func testRMSSD_knownValues() {
        // RR intervals: 800, 820, 790, 810, 830 ms
        // Successive differences: 20, -30, 20, 20
        // Squared: 400, 900, 400, 400 → mean = 525 → RMSSD = sqrt(525) ≈ 22.91
        let processor = HRVProcessor()
        let base = Date()
        [800.0, 820.0, 790.0, 810.0, 830.0].enumerated().forEach { i, rr in
            processor.addRRInterval(rr, at: base.addingTimeInterval(Double(i) * 0.85))
        }
        let result = processor.rmssd
        XCTAssertNotNil(result)
        XCTAssertEqual(result!, sqrt(525.0), accuracy: 0.01)
    }

    func testRMSSD_twoSamples() {
        let processor = HRVProcessor()
        processor.addRRInterval(800)
        processor.addRRInterval(820)
        // diff = 20 → rmssd = sqrt(400/1) = 20
        XCTAssertEqual(processor.rmssd!, 20.0, accuracy: 0.001)
    }

    func testRMSSD_singleSample_returnsNil() {
        let processor = HRVProcessor()
        processor.addRRInterval(800)
        XCTAssertNil(processor.rmssd)
    }

    func testRMSSD_empty_returnsNil() {
        XCTAssertNil(HRVProcessor().rmssd)
    }

    // MARK: - Rolling window

    func testRollingWindow_prunesOldSamples() {
        let processor = HRVProcessor(windowDuration: 1.0)
        let base = Date()
        processor.addRRInterval(800, at: base.addingTimeInterval(-2.0))  // outside window
        processor.addRRInterval(810, at: base.addingTimeInterval(-0.5))  // inside
        processor.addRRInterval(820, at: base)                            // inside
        XCTAssertEqual(processor.currentWindow.count, 2)
    }

    func testReset_clearsWindow() {
        let processor = HRVProcessor()
        processor.addRRInterval(800)
        processor.addRRInterval(810)
        processor.reset()
        XCTAssertNil(processor.rmssd)
        XCTAssertTrue(processor.currentWindow.isEmpty)
    }
}
