import GRDB

public struct AppMigrations: Sendable {
    public static func registerAll(in migrator: inout DatabaseMigrator) {
        registerV1(in: &migrator)
        registerV2(in: &migrator)
        registerV3(in: &migrator)
        registerV4(in: &migrator)
    }

    // MARK: - V1: Projects and Tasks

    private static func registerV1(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v1_projects_tasks") { db in
            try db.create(table: "projects") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("createdAt", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
            }

            try db.create(table: "tasks") { t in
                t.autoIncrementedPrimaryKey("id")
                t.belongsTo("project", inTable: "projects")
                t.column("title", .text).notNull()
                t.column("estimateMinutes", .integer)
                t.column("priority", .integer).notNull().defaults(to: 1)
                t.column("status", .integer).notNull().defaults(to: 0)
                t.column("dueDate", .datetime)
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
                t.column("createdAt", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
                t.column("updatedAt", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
            }
        }
    }

    // MARK: - V2: Sessions and Session Events

    private static func registerV2(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v2_sessions") { db in
            try db.create(table: "sessions") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("startTime", .datetime).notNull()
                t.column("endTime", .datetime)
                t.column("durationSeconds", .integer).notNull().defaults(to: 0)
                t.column("focusedSeconds", .integer).notNull().defaults(to: 0)
                t.column("distractionCount", .integer).notNull().defaults(to: 0)
                t.column("isComplete", .boolean).notNull().defaults(to: false)
                t.column("createdAt", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
            }

            try db.create(table: "session_events") { t in
                t.autoIncrementedPrimaryKey("id")
                t.belongsTo("session", inTable: "sessions")
                t.column("eventType", .text).notNull()
                t.column("timestamp", .datetime).notNull()
                t.column("appName", .text)
                t.column("durationSeconds", .integer)
                t.column("metadata", .text)
            }
        }
    }

    // MARK: - V3: Blocklist Items

    private static func registerV3(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v3_blocklist") { db in
            try db.create(table: "blocklist_items") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("bundleId", .text)
                t.column("domain", .text)
                t.column("displayName", .text).notNull()
                t.column("blockMode", .integer).notNull().defaults(to: 0)
                t.column("isEnabled", .boolean).notNull().defaults(to: true)
                t.column("createdAt", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
            }
        }
    }

    // MARK: - V4: Sync Columns

    private static func registerV4(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v4_sync_columns") { db in
            try db.alter(table: "projects") { t in
                t.add(column: "remoteId", .text)
                t.add(column: "syncStatus", .integer).notNull().defaults(to: 0)
                t.add(column: "lastSyncedAt", .datetime)
            }

            try db.alter(table: "tasks") { t in
                t.add(column: "remoteId", .text)
                t.add(column: "syncStatus", .integer).notNull().defaults(to: 0)
                t.add(column: "lastSyncedAt", .datetime)
            }

            try db.alter(table: "sessions") { t in
                t.add(column: "remoteId", .text)
                t.add(column: "syncStatus", .integer).notNull().defaults(to: 0)
                t.add(column: "lastSyncedAt", .datetime)
            }

            try db.alter(table: "session_events") { t in
                t.add(column: "remoteId", .text)
                t.add(column: "syncStatus", .integer).notNull().defaults(to: 0)
                t.add(column: "lastSyncedAt", .datetime)
            }

            try db.execute(sql: """
                CREATE INDEX idx_projects_pending_sync ON projects(syncStatus)
                WHERE syncStatus != 1
                """)
            try db.execute(sql: """
                CREATE INDEX idx_tasks_pending_sync ON tasks(syncStatus)
                WHERE syncStatus != 1
                """)
            try db.execute(sql: """
                CREATE INDEX idx_sessions_pending_sync ON sessions(syncStatus)
                WHERE syncStatus != 1
                """)
            try db.execute(sql: """
                CREATE INDEX idx_session_events_pending_sync ON session_events(syncStatus)
                WHERE syncStatus != 1
                """)
        }
    }
}
