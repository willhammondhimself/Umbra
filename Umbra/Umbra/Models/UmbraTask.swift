import Foundation
import GRDB

struct UmbraTask: Identifiable, Codable, Equatable {
    var id: Int64?
    var projectId: Int64?
    var title: String
    var estimateMinutes: Int?
    var priority: Priority
    var status: Status
    var dueDate: Date?
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date
    var remoteId: UUID?
    var syncStatus: SyncStatus
    var lastSyncedAt: Date?

    init(
        id: Int64? = nil,
        projectId: Int64? = nil,
        title: String,
        estimateMinutes: Int? = nil,
        priority: Priority = .medium,
        status: Status = .todo,
        dueDate: Date? = nil,
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        remoteId: UUID? = nil,
        syncStatus: SyncStatus = .local,
        lastSyncedAt: Date? = nil
    ) {
        self.id = id
        self.projectId = projectId
        self.title = title
        self.estimateMinutes = estimateMinutes
        self.priority = priority
        self.status = status
        self.dueDate = dueDate
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.remoteId = remoteId
        self.syncStatus = syncStatus
        self.lastSyncedAt = lastSyncedAt
    }

    enum Priority: Int, Codable, CaseIterable, Comparable {
        case low = 0
        case medium = 1
        case high = 2
        case urgent = 3

        var label: String {
            switch self {
            case .low: "Low"
            case .medium: "Medium"
            case .high: "High"
            case .urgent: "Urgent"
            }
        }

        var iconName: String {
            switch self {
            case .low: "arrow.down"
            case .medium: "minus"
            case .high: "arrow.up"
            case .urgent: "exclamationmark.2"
            }
        }

        static func < (lhs: Priority, rhs: Priority) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    enum Status: Int, Codable, CaseIterable {
        case todo = 0
        case inProgress = 1
        case done = 2

        var label: String {
            switch self {
            case .todo: "To Do"
            case .inProgress: "In Progress"
            case .done: "Done"
            }
        }
    }
}

// MARK: - GRDB Conformance

extension UmbraTask: FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "tasks"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    static let project = belongsTo(Project.self)

    var project: QueryInterfaceRequest<Project> {
        request(for: UmbraTask.project)
    }
}

// MARK: - Formatted Estimate

extension UmbraTask {
    var formattedEstimate: String? {
        guard let minutes = estimateMinutes else { return nil }
        if minutes < 60 {
            return "\(minutes)m"
        }
        let hours = minutes / 60
        let remainder = minutes % 60
        if remainder == 0 {
            return "\(hours)h"
        }
        return "\(hours)h \(remainder)m"
    }
}
