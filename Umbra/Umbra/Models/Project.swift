import Foundation
import GRDB

struct Project: Identifiable, Codable, Equatable {
    var id: Int64?
    var name: String
    var createdAt: Date
    var remoteId: UUID?
    var syncStatus: SyncStatus
    var lastSyncedAt: Date?

    init(
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
    static let databaseTableName = "projects"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    static let tasks = hasMany(UmbraTask.self)

    var tasks: QueryInterfaceRequest<UmbraTask> {
        request(for: Project.tasks)
    }
}
