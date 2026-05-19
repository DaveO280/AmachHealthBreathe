import Foundation
import AmachBreatheShared

/// Local iPhone-side record mirroring the Watch's BreathingSessionRecord,
/// with an added upload status for async Storj sync.
public struct SessionRecord: Identifiable, Codable, Sendable {
    public let id: String
    public let breathingSession: BreathingSessionRecord
    public var uploadStatus: UploadStatus
    public var storjUri: String?
    public var coaching: SessionCoachingState

    public enum UploadStatus: String, Codable, Sendable {
        case pending, uploaded, failed
    }

    public init(
        from session: BreathingSessionRecord,
        uploadStatus: UploadStatus = .pending,
        storjUri: String? = nil,
        coaching: SessionCoachingState = SessionCoachingState()
    ) {
        self.id = session.id
        self.breathingSession = session
        self.uploadStatus = uploadStatus
        self.storjUri = storjUri
        self.coaching = coaching
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        breathingSession = try container.decode(BreathingSessionRecord.self, forKey: .breathingSession)
        uploadStatus = try container.decode(UploadStatus.self, forKey: .uploadStatus)
        storjUri = try container.decodeIfPresent(String.self, forKey: .storjUri)
        coaching = try container.decodeIfPresent(SessionCoachingState.self, forKey: .coaching)
            ?? SessionCoachingState()
    }
}
