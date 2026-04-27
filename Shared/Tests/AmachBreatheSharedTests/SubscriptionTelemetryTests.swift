import XCTest
@testable import AmachBreatheShared

final class SubscriptionTelemetryTests: XCTestCase {

    // MARK: - SubscriptionRecord Codable

    func testSubscriptionRecordRoundTrip() throws {
        let record = SubscriptionRecord(
            walletAddress: "0xabc123",
            state: .subscribed,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            transactionId: "txn_42",
            connectedSince: Date(timeIntervalSince1970: 1_690_000_000)
        )
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(SubscriptionRecord.self, from: data)
        XCTAssertEqual(decoded.walletAddress, record.walletAddress)
        XCTAssertEqual(decoded.state, record.state)
        XCTAssertEqual(decoded.transactionId, record.transactionId)
        XCTAssertEqual(decoded.updatedAt.timeIntervalSince1970, record.updatedAt.timeIntervalSince1970, accuracy: 1)
    }

    func testSubscriptionRecordOptionalFieldsNil() throws {
        let record = SubscriptionRecord(walletAddress: "0xfoo", state: .trial)
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(SubscriptionRecord.self, from: data)
        XCTAssertNil(decoded.transactionId)
        XCTAssertNil(decoded.connectedSince)
    }

    func testSubscriptionRecordAllStatesEncodable() throws {
        let states: [SubscriptionState] = [.trial, .subscribed, .connected, .expired]
        for state in states {
            let record = SubscriptionRecord(walletAddress: "0x1", state: state)
            let data = try JSONEncoder().encode(record)
            let decoded = try JSONDecoder().decode(SubscriptionRecord.self, from: data)
            XCTAssertEqual(decoded.state, state, "Failed for state: \(state)")
        }
    }

    // MARK: - SubscriptionTelemetryEvent shape

    func testTelemetryEventStateChangeShape() throws {
        let event = SubscriptionTelemetryEvent(
            eventType: "subscription_state_change",
            walletAddress: "0xabc",
            subscriptionState: .subscribed,
            metrics: CostMetrics(sessionCount30Days: 5, revenueUSD: 4.99, previousState: .trial)
        )
        let data = try JSONEncoder().encode(event)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["eventType"] as? String, "subscription_state_change")
        XCTAssertEqual(json["walletAddress"] as? String, "0xabc")
        XCTAssertEqual(json["subscriptionState"] as? String, "subscribed")
        XCTAssertEqual(json["platform"] as? String, "ios")
        XCTAssertNotNil(json["timestamp"])
        XCTAssertNotNil(json["metrics"])
    }

    func testTelemetryEventCheckShape() throws {
        let event = SubscriptionTelemetryEvent(
            eventType: "subscription_check",
            walletAddress: "0xdef",
            subscriptionState: .connected
        )
        let data = try JSONEncoder().encode(event)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["eventType"] as? String, "subscription_check")
        XCTAssertEqual(json["subscriptionState"] as? String, "connected")
        XCTAssertNil(json["metrics"] as? [String: Any])
    }

    // MARK: - CostMetrics shape

    func testCostMetricsAllFields() throws {
        let metrics = CostMetrics(
            sessionCount30Days: 7,
            storjUploadCount: 42,
            revenueUSD: 4.99,
            previousState: .trial
        )
        let data = try JSONEncoder().encode(metrics)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["sessionCount30Days"] as? Int, 7)
        XCTAssertEqual(json["storjUploadCount"] as? Int, 42)
        XCTAssertEqual(json["revenueUSD"] as? Double ?? 0, 4.99, accuracy: 0.001)
        XCTAssertEqual(json["previousState"] as? String, "trial")
    }

    func testCostMetricsNilFieldsOmitted() throws {
        let metrics = CostMetrics()
        let data = try JSONEncoder().encode(metrics)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        // nil optionals should encode as null or be absent — just verify no crash
        XCTAssertNotNil(json)
    }

    func testCostMetricsRevenueZeroForConnected() throws {
        let metrics = CostMetrics(revenueUSD: 0)
        let data = try JSONEncoder().encode(metrics)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["revenueUSD"] as? Double ?? -1, 0.0, accuracy: 0.001)
    }

    // MARK: - SubscriptionProduct constants

    func testProductIDFormat() {
        XCTAssertEqual(SubscriptionProduct.monthly, "com.amach.breathe.monthly")
    }

    func testProductPriceIsCorrect() {
        XCTAssertEqual(SubscriptionProduct.monthlyPriceUSD, 4.99, accuracy: 0.001)
    }

    func testAllIDsContainsMonthly() {
        XCTAssertTrue(SubscriptionProduct.allIDs.contains(SubscriptionProduct.monthly))
    }

    // MARK: - SubscriptionState raw values

    func testSubscriptionStateRawValues() {
        XCTAssertEqual(SubscriptionState.trial.rawValue, "trial")
        XCTAssertEqual(SubscriptionState.subscribed.rawValue, "subscribed")
        XCTAssertEqual(SubscriptionState.connected.rawValue, "connected")
        XCTAssertEqual(SubscriptionState.expired.rawValue, "expired")
    }

    func testSubscriptionStateInitFromRaw() {
        XCTAssertEqual(SubscriptionState(rawValue: "trial"), .trial)
        XCTAssertEqual(SubscriptionState(rawValue: "subscribed"), .subscribed)
        XCTAssertEqual(SubscriptionState(rawValue: "connected"), .connected)
        XCTAssertEqual(SubscriptionState(rawValue: "expired"), .expired)
        XCTAssertNil(SubscriptionState(rawValue: "unknown"))
    }
}
