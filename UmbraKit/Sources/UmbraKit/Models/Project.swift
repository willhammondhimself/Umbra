import Foundation
import GRDB

public struct Project: Identifiable, Codable, Equatable, Sendable {
    public var id: Int64?
    public var name: String
    public var createdAt: Date
    public var remoteId: UUID?
    public var syncStatus: SyncStatus
    public var lastSyncedAt: Date?

    public init(
        id: Int64? = nil,
        name: String,
        createdAt: Date = Date(),
        remoteId: UUID? = nil,
        syncStatus: SyncStatus = .local,
        lastSyncedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.remoteId = remoteId
        self.syncStatus = syncStatus
        self.lastSyncedAt = lastSyncedAt
    }
}

// MARK: - GRDB Conformance

extension Project: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "projects"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    public static let tasks = hasMany(UmbraTask.self)

    public var tasks: QueryInterfaceRequest<UmbraTask> {
        request(for: Project.tasks)
    }
}
