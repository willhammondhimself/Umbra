import Foundation
import GRDB

@MainActor
public final class DatabaseManager {
    public static let shared = DatabaseManager()

    public let dbQueue: DatabaseQueue

    private init() {
        do {
            let fileManager = FileManager.default
            let appSupportURL = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let umbraDir = appSupportURL.appendingPathComponent("Umbra", isDirectory: true)
            try fileManager.createDirectory(at: umbraDir, withIntermediateDirectories: true)

            let dbURL = umbraDir.appendingPathComponent("umbra.sqlite")
            var config = Configuration()
            #if DEBUG
            config.prepareDatabase { db in
                db.trace { print("SQL: \($0)") }
            }
            #endif

            dbQueue = try DatabaseQueue(path: dbURL.path, configuration: config)

            var migrator = DatabaseMigrator()
            #if DEBUG
            migrator.eraseDatabaseOnSchemaChange = true
            #endif
            AppMigrations.registerAll(in: &migrator)
            try migrator.migrate(dbQueue)
        } catch {
            fatalError("Database setup failed: \(error)")
        }
    }

    // MARK: - Projects

    public func fetchProjects() throws -> [Project] {
        try dbQueue.read { db in
            try Project.order(Column("createdAt").desc).fetchAll(db)
        }
    }

    public func saveProject(_ project: inout Project) throws {
        try dbQueue.write { db in
            try project.save(db)
        }
    }

    public func deleteProject(_ project: Project) throws {
        try dbQueue.write { db in
            _ = try project.delete(db)
        }
    }

    // MARK: - Tasks

    public func fetchTasks(projectId: Int64? = nil) throws -> [UmbraTask] {
        try dbQueue.read { db in
            var request = UmbraTask.order(
                Column("status").asc,
                Column("priority").desc,
                Column("sortOrder").asc
            )
            if let projectId {
                request = request.filter(Column("projectId") == projectId)
            }
            return try request.fetchAll(db)
        }
    }

    public func saveTask(_ task: inout UmbraTask) throws {
        task.updatedAt = Date()
        try dbQueue.write { db in
            try task.save(db)
        }
    }

    public func deleteTask(_ task: UmbraTask) throws {
        try dbQueue.write { db in
            _ = try task.delete(db)
        }
    }

    public func updateTaskOrder(taskId: Int64, newOrder: Int) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE tasks SET sortOrder = ?, updatedAt = ? WHERE id = ?",
                arguments: [newOrder, Date(), taskId]
            )
        }
    }

    public func nextSortOrder(projectId: Int64?) throws -> Int {
        try dbQueue.read { db in
            var sql = "SELECT COALESCE(MAX(sortOrder), -1) + 1 FROM tasks"
            var arguments: StatementArguments = []
            if let projectId {
                sql += " WHERE projectId = ?"
                arguments = [projectId]
            }
            return try Int.fetchOne(db, sql: sql, arguments: arguments) ?? 0
        }
    }

    // MARK: - Sessions

    public func saveSession(_ session: inout Session) throws {
        try dbQueue.write { db in
            try session.save(db)
        }
    }

    public func fetchSessions(limit: Int = 50) throws -> [Session] {
        try dbQueue.read { db in
            try Session
                .order(Column("startTime").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    public func fetchIncompleteSession() throws -> Session? {
        try dbQueue.read { db in
            try Session
                .filter(Column("isComplete") == false)
                .order(Column("startTime").desc)
                .fetchOne(db)
        }
    }

    // MARK: - Session Events

    public func saveEvent(_ event: inout SessionEvent) throws {
        try dbQueue.write { db in
            try event.save(db)
        }
    }

    public func fetchEvents(sessionId: Int64) throws -> [SessionEvent] {
        try dbQueue.read { db in
            try SessionEvent
                .filter(Column("sessionId") == sessionId)
                .order(Column("timestamp").asc)
                .fetchAll(db)
        }
    }

    // MARK: - Blocklist Items

    public func fetchBlocklistItems() throws -> [BlocklistItem] {
        try dbQueue.read { db in
            try BlocklistItem.order(Column("displayName").asc).fetchAll(db)
        }
    }

    public func saveBlocklistItem(_ item: inout BlocklistItem) throws {
        try dbQueue.write { db in
            try item.save(db)
        }
    }

    public func deleteBlocklistItem(_ item: BlocklistItem) throws {
        try dbQueue.write { db in
            _ = try item.delete(db)
        }
    }

    // MARK: - Sync Operations

    public func fetchPendingProjects() throws -> [Project] {
        try dbQueue.read { db in
            try Project.filter(Column("syncStatus") != SyncStatus.synced.rawValue).fetchAll(db)
        }
    }

    public func fetchPendingTasks() throws -> [UmbraTask] {
        try dbQueue.read { db in
            try UmbraTask.filter(Column("syncStatus") != SyncStatus.synced.rawValue).fetchAll(db)
        }
    }

    public func fetchPendingSessions() throws -> [Session] {
        try dbQueue.read { db in
            try Session.filter(Column("syncStatus") != SyncStatus.synced.rawValue).fetchAll(db)
        }
    }

    public func fetchPendingEvents() throws -> [SessionEvent] {
        try dbQueue.read { db in
            try SessionEvent.filter(Column("syncStatus") != SyncStatus.synced.rawValue).fetchAll(db)
        }
    }

    public func updateSyncStatus<T: MutablePersistableRecord & Identifiable>(
        _ record: inout T,
        status: SyncStatus,
        remoteId: UUID? = nil
    ) throws where T.ID == Int64? {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    UPDATE \(T.databaseTableName)
                    SET syncStatus = ?, remoteId = COALESCE(?, remoteId), lastSyncedAt = ?
                    WHERE id = ?
                    """,
                arguments: [status.rawValue, remoteId?.uuidString, Date(), record.id]
            )
        }
    }

    public func upsertProjectFromRemote(remoteId: UUID, name: String, createdAt: Date) throws {
        try dbQueue.write { db in
            if let existing = try Project
                .filter(Column("remoteId") == remoteId.uuidString)
                .fetchOne(db)
            {
                try db.execute(
                    sql: "UPDATE projects SET name = ?, syncStatus = ?, lastSyncedAt = ? WHERE id = ?",
                    arguments: [name, SyncStatus.synced.rawValue, Date(), existing.id]
                )
            } else {
                var project = Project(name: name, createdAt: createdAt, remoteId: remoteId, syncStatus: .synced, lastSyncedAt: Date())
                try project.insert(db)
            }
        }
    }

    public func upsertTaskFromRemote(remoteId: UUID, title: String, priority: Int, status: Int, estimateMinutes: Int?, dueDate: Date?, sortOrder: Int, createdAt: Date, updatedAt: Date) throws {
        try dbQueue.write { db in
            if let existing = try UmbraTask
                .filter(Column("remoteId") == remoteId.uuidString)
                .fetchOne(db)
            {
                try db.execute(
                    sql: """
                        UPDATE tasks SET title = ?, priority = ?, status = ?, estimateMinutes = ?,
                        dueDate = ?, sortOrder = ?, updatedAt = ?, syncStatus = ?, lastSyncedAt = ?
                        WHERE id = ?
                        """,
                    arguments: [title, priority, status, estimateMinutes, dueDate, sortOrder, updatedAt, SyncStatus.synced.rawValue, Date(), existing.id]
                )
            } else {
                var task = UmbraTask(
                    title: title,
                    estimateMinutes: estimateMinutes,
                    priority: UmbraTask.Priority(rawValue: priority) ?? .medium,
                    status: UmbraTask.Status(rawValue: status) ?? .todo,
                    dueDate: dueDate,
                    sortOrder: sortOrder,
                    createdAt: createdAt,
                    updatedAt: updatedAt,
                    remoteId: remoteId,
                    syncStatus: .synced,
                    lastSyncedAt: Date()
                )
                try task.insert(db)
            }
        }
    }

    public func fetchLastSyncDate(for entity: String) throws -> Date? {
        try dbQueue.read { db in
            let row = try Row.fetchOne(db, sql: """
                SELECT MAX(lastSyncedAt) as lastSync FROM \(entity)
                WHERE syncStatus = ?
                """, arguments: [SyncStatus.synced.rawValue])
            return row?["lastSync"]
        }
    }
}
