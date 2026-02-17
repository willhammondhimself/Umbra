import Foundation
import GRDB

public struct UmbraTask: Identifiable, Codable, Equatable, Sendable {
    public var id: Int64?
    public var projectId: Int64?
    public var title: String
    public var estimateMinutes: Int?
    public var priority: Priority
    public var status: Status
    public var dueDate: Date?
    public var sortOrder: Int
    public var createdAt: Date
    public var updatedAt: Date
    public var remoteId: UUID?
    public var syncStatus: SyncStatus
    public var lastSyncedAt: Date?

    public init(
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

    public enum Priority: Int, Codable, CaseIterable, Comparable, Sendable {
        case low = 0
        case medium = 1
        case high = 2
        case urgent = 3

        public var label: String {
            switch self {
            case .low: "Low"
            case .medium: "Medium"
            case .high: "High"
            case .urgent: "Urgent"
            }
        }

        public var iconName: String {
            switch self {
            case .low: "arrow.down"
            case .medium: "minus"
            case .high: "arrow.up"
            case .urgent: "exclamationmark.2"
            }
        }

        public static func < (lhs: Priority, rhs: Priority) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    public enum Status: Int, Codable, CaseIterable, Sendable {
        case todo = 0
        case inProgress = 1
        case done = 2

        public var label: String {
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
    public static let databaseTableName = "tasks"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    public static let project = belongsTo(Project.self)

    public var project: QueryInterfaceRequest<Project> {
        request(for: UmbraTask.project)
    }
}

// MARK: - Formatted Estimate

extension UmbraTask {
    public var formattedEstimate: String? {
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
