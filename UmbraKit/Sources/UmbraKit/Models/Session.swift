import Foundation
import GRDB

public struct Session: Identifiable, Codable, Equatable, Sendable {
    public var id: Int64?
    public var startTime: Date
    public var endTime: Date?
    public var durationSeconds: Int
    public var focusedSeconds: Int
    public var distractionCount: Int
    public var isComplete: Bool
    public var createdAt: Date
    public var remoteId: UUID?
    public var syncStatus: SyncStatus
    public var lastSyncedAt: Date?

    public init(
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

    public var formattedDuration: String {
        Self.formatSeconds(durationSeconds)
    }

    public var formattedFocused: String {
        Self.formatSeconds(focusedSeconds)
    }

    public var focusPercentage: Double {
        guard durationSeconds > 0 else { return 0 }
        return Double(focusedSeconds) / Double(durationSeconds) * 100
    }

    public static func formatSeconds(_ seconds: Int) -> String {
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
    public static let databaseTableName = "sessions"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    public static let events = hasMany(SessionEvent.self)

    public var events: QueryInterfaceRequest<SessionEvent> {
        request(for: Session.events)
    }
}
