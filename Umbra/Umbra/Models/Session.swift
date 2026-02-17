import Foundation
import GRDB

struct Session: Identifiable, Codable, Equatable {
    var id: Int64?
    var startTime: Date
    var endTime: Date?
    var durationSeconds: Int
    var focusedSeconds: Int
    var distractionCount: Int
    var isComplete: Bool
    var createdAt: Date
    var remoteId: UUID?
    var syncStatus: SyncStatus
    var lastSyncedAt: Date?

    init(
        id: Int64? = nil,
        startTime: Date = Date(),
        endTime: Date? = nil,
        durationSeconds: Int = 0,
        focusedSeconds: Int = 0,
        distractionCount: Int = 0,
        isComplete: Bool = false,
        createdAt: Date = Date(),
        remoteId: UUID? = nil,
        syncStatus: SyncStatus = .local,
        lastSyncedAt: Date? = nil
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.durationSeconds = durationSeconds
        self.focusedSeconds = focusedSeconds
        self.distractionCount = distractionCount
        self.isComplete = isComplete
        self.createdAt = createdAt
        self.remoteId = remoteId
        self.syncStatus = syncStatus
        self.lastSyncedAt = lastSyncedAt
    }

    var formattedDuration: String {
        Self.formatSeconds(durationSeconds)
    }

    var formattedFocused: String {
        Self.formatSeconds(focusedSeconds)
    }

    var focusPercentage: Double {
        guard durationSeconds > 0 else { return 0 }
        return Double(focusedSeconds) / Double(durationSeconds) * 100
    }

    static func formatSeconds(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - GRDB

extension Session: FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "sessions"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    static let events = hasMany(SessionEvent.self)

    var events: QueryInterfaceRequest<SessionEvent> {
        request(for: Session.events)
    }
}
