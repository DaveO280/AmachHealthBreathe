import Foundation

public enum DiagnosticLevel: String, Codable, Sendable {
    case info
    case warning
    case error
}

public struct DiagnosticEvent: Codable, Identifiable, Sendable {
    public let id: String
    public let timestamp: Date
    public let source: String
    public let category: String
    public let level: DiagnosticLevel
    public let message: String
    public let metadata: [String: String]

    public init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        source: String,
        category: String,
        level: DiagnosticLevel = .info,
        message: String,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.source = source
        self.category = category
        self.level = level
        self.message = message
        self.metadata = metadata
    }
}

public final class DiagnosticLog: @unchecked Sendable {

    public static let shared = DiagnosticLog()

    private let lock = NSLock()
    private let storageKey = "com.amach.breathe.diagnosticEvents"
    private let maxEvents = 150
    private var events: [DiagnosticEvent] = []

    private init() {
        events = Self.loadEvents(storageKey: storageKey)
    }

    public func record(
        source: String,
        category: String,
        level: DiagnosticLevel = .info,
        message: String,
        metadata: [String: String] = [:]
    ) {
        append(DiagnosticEvent(
            source: source,
            category: category,
            level: level,
            message: message,
            metadata: metadata
        ))
    }

    public func append(_ event: DiagnosticEvent) {
        lock.lock()
        events.append(event)
        if events.count > maxEvents {
            events.removeFirst(events.count - maxEvents)
        }
        let snapshot = events
        lock.unlock()
        Self.persist(snapshot, storageKey: storageKey)
    }

    public func snapshot() -> [DiagnosticEvent] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }

    public func clear() {
        lock.lock()
        events.removeAll()
        lock.unlock()
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    private static func loadEvents(storageKey: String) -> [DiagnosticEvent] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([DiagnosticEvent].self, from: data) else {
            return []
        }
        return decoded
    }

    private static func persist(_ events: [DiagnosticEvent], storageKey: String) {
        guard let data = try? JSONEncoder().encode(events) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
