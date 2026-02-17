import Foundation
import GRDB

public struct SessionEvent: Identifiable, Codable, Equatable, Sendable {
    public var id: Int64?
    public var sessionId: Int64
    public var eventType: EventType
    public var timestamp: Date
    public var appName: String?
    public var durationSeconds: Int?
    public var metadata: String?
    public var remoteId: UUID?
    public var syncStatus: SyncStatus
    public var lastSyncedAt: Date?

    public init(
        id: Int64? = nil,
        sessionId: Int64,
        eventType: EventType,
        timestamp: Date = Date(),
        appName: String? = nil,
        durationSeconds: Int? = nil,
        metadata: String? = nil,
        remoteId: UUID? = nil,
        syncStatus: SyncStatus = .local,
        lastSyncedAt: Date? = nil
    ) {
        self.id = id
        self.sessionId = sessionId
        self.eventType = eventType
        self.timestamp = timestamp
        self.appName = appName
        self.durationSeconds = durationSeconds
        self.metadata = metadata
        self.remoteId = remoteId
        self.syncStatus = syncStatus
        self.lastSyncedAt = lastSyncedAt
    }

    public enum EventType: String, Codable, CaseIterable, Sendable {
        case start = "START"
        case pause = "PAUSE"
        case resume = "RESUME"
        case stop = "STOP"
        case taskComplete = "TASK_COMPLETE"
        case distraction = "DISTRACTION"
        case idle = "IDLE"
    }
}

// MARK: - GRDB

extension SessionEvent: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "session_events"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    public static let session = belongsTo(Session.self)
}
