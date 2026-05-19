import XCTest
@testable import AmachBreatheShared

final class CoachingInsightTests: XCTestCase {

    private let encoder = JSONEncoder()

    func testCoachingHistoryEncodesInRequest() throws {
        let history: [CoachingHistoryMessage] = [
            .user("Summarize my session"),
            .assistant("Your coherence was steady.")
        ]
        let request = CoachingInsightRequest(
            facts: makeFacts(),
            history: history,
            message: "Why was coherence low?"
        )
        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let encodedHistory = json["history"] as? [[String: String]]

        XCTAssertEqual(json["message"] as? String, "Why was coherence low?")
        XCTAssertEqual(encodedHistory?.count, 2)
        XCTAssertEqual(encodedHistory?.first?["role"], "user")
        XCTAssertEqual(encodedHistory?.last?["role"], "assistant")
    }

    func testInitialPromptReferencesAudioWhenQualityFairOrBetter() {
        let facts = makeFacts(
            audio: CoachingAudioFacts(
                enabled: true,
                permissionGranted: true,
                targetBreathingBPM: 5.5,
                estimatedBreathingBPM: 5.4,
                adherenceScore: 0.88,
                confidence: 0.55,
                dataQuality: .fair,
                analyzedDurationSeconds: 280,
                detectedPeakCount: 22
            )
        )
        let prompt = CoachingInsightRequest.initialPrompt(for: facts)
        XCTAssertTrue(prompt.contains("estimated BPM"))
        XCTAssertTrue(prompt.contains("adherence"))
    }

    func testInitialPromptNotesWeakAudioWhenQualityLow() {
        let facts = makeFacts(
            audio: CoachingAudioFacts(
                enabled: true,
                permissionGranted: true,
                targetBreathingBPM: 5.5,
                confidence: 0.2,
                dataQuality: .low,
                analyzedDurationSeconds: 30,
                detectedPeakCount: 1
            )
        )
        let prompt = CoachingInsightRequest.initialPrompt(for: facts)
        XCTAssertTrue(prompt.contains("low quality") || prompt.contains("limited"))
    }

    func testSessionCoachingStateRoundTrip() throws {
        let state = SessionCoachingState(
            messages: [
                .user("Summarize my session"),
                .assistant("Nice steady pace.")
            ],
            lastInsight: CoachingInsight(content: "Nice steady pace.")
        )
        let data = try encoder.encode(state)
        let decoded = try JSONDecoder().decode(SessionCoachingState.self, from: data)
        XCTAssertEqual(decoded, state)
    }

    private func makeFacts(audio: CoachingAudioFacts? = nil) -> CoachingSessionFacts {
        CoachingSessionFacts(
            sessionId: "test-session",
            timestampISO8601: "2024-01-01T00:00:00Z",
            durationSeconds: 300,
            targetBreathingBPM: 5.5,
            ratio: "4:6",
            source: .phone,
            avgHRV: 52,
            coherenceScore: 0.61,
            reflectionRating: 4,
            audio: audio
        )
    }
}
