import Foundation
import GRDB

struct SessionEvent: Identifiable, Codable, Equatable {
    var id: Int64?
    var sessionId: Int64
    var eventType: EventType
    var timestamp: Date
    var appName: String?
    var durationSeconds: Int?
    var metadata: String?
    var remoteId: UUID?
    var syncStatus: SyncStatus
    var lastSyncedAt: Date?

    init(
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

    enum EventType: String, Codable, CaseIterable {
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
    static let databaseTableName = "session_events"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    static let session = belongsTo(Session.self)
}
