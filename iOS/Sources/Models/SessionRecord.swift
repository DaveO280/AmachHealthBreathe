import Foundation
import AmachBreatheShared

/// Local iPhone-side record mirroring the Watch's BreathingSessionRecord,
/// with an added upload status for async Storj sync.
public struct SessionRecord: Identifiable, Codable, Sendable {
    public let id: String
    public let breathingSession: BreathingSessionRecord
    public var uploadStatus: UploadStatus
    public var storjUri: String?

    public enum UploadStatus: String, Codable, Sendable {
        case pending, uploaded, failed
    }

    public init(from session: BreathingSessionRecord, uploadStatus: UploadStatus = .pending, storjUri: String? = nil) {
        self.id = session.id
        self.breathingSession = session
        self.uploadStatus = uploadStatus
        self.storjUri = storjUri
    }
}
