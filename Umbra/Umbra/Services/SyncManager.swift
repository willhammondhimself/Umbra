import Foundation
import Network

@MainActor
@Observable
final class SyncManager {
    static let shared = SyncManager()

    private(set) var isSyncing = false
    private(set) var isOnline = false
    private(set) var lastSyncDate: Date?

    private var syncTimer: Task<Void, Never>?
    private let pathMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.umbra.network-monitor")

    private init() {
        startNetworkMonitoring()
        startPeriodicSync()
    }

    // MARK: - Network Monitoring

    private func startNetworkMonitoring() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isOnline = path.status == .satisfied
                if path.status == .satisfied {
                    self?.triggerSync()
                }
            }
        }
        pathMonitor.start(queue: monitorQueue)
    }

    // MARK: - Periodic Sync (10s)

    private func startPeriodicSync() {
        syncTimer?.cancel()
        syncTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { break }
                await self?.triggerSync()
            }
        }
    }

    // MARK: - Sync Trigger

    func triggerSync() {
        guard isOnline, !isSyncing else { return }
        guard AuthManager.shared.isAuthenticated else { return }

        Task {
            await performSync()
        }
    }

    // MARK: - Sync Pipeline

    private func performSync() async {
        isSyncing = true
        defer { isSyncing = false }

        do {
            // 1. Upload pending creations
            try await uploadPendingProjects()
            try await uploadPendingTasks()

            // 2. Upload pending updates
            try await uploadPendingUpdates()

            // 3. Pull remote changes
            try await pullRemoteProjects()
            try await pullRemoteTasks()

            lastSyncDate = Date()
        } catch {
            print("Sync failed: \(error)")
        }
    }

    // MARK: - Upload Pending Projects

    private func uploadPendingProjects() async throws {
        let pending = try DatabaseManager.shared.fetchPendingProjects()

        for var project in pending {
            guard project.syncStatus == .pendingUpload || project.syncStatus == .local else { continue }

            let body = ["name": project.name]
            do {
                let remote: RemoteProject = try await APIClient.shared.request(
                    .projects, method: "POST", body: body
                )
                try DatabaseManager.shared.updateSyncStatus(
                    &project, status: .synced, remoteId: remote.id
                )
            } catch {
                print("Failed to upload project \(project.name): \(error)")
            }
        }
    }

    // MARK: - Upload Pending Tasks

    private func uploadPendingTasks() async throws {
        let pending = try DatabaseManager.shared.fetchPendingTasks()

        for var task in pending {
            guard task.syncStatus == .pendingUpload || task.syncStatus == .local else { continue }

            let body = TaskUploadBody(
                title: task.title,
                priority: task.priority.rawValue,
                status: task.status.rawValue,
                estimateMinutes: task.estimateMinutes,
                sortOrder: task.sortOrder
            )
            do {
                let remote: RemoteTask = try await APIClient.shared.request(
                    .tasks, method: "POST", body: body
                )
                try DatabaseManager.shared.updateSyncStatus(
                    &task, status: .synced, remoteId: remote.id
                )
            } catch {
                print("Failed to upload task \(task.title): \(error)")
            }
        }
    }

    // MARK: - Upload Pending Updates

    private func uploadPendingUpdates() async throws {
        let pendingTasks = try DatabaseManager.shared.fetchPendingTasks()
            .filter { $0.syncStatus == .pendingUpdate && $0.remoteId != nil }

        for var task in pendingTasks {
            guard let remoteId = task.remoteId else { continue }
            let body = TaskUploadBody(
                title: task.title,
                priority: task.priority.rawValue,
                status: task.status.rawValue,
                estimateMinutes: task.estimateMinutes,
                sortOrder: task.sortOrder
            )
            do {
                let _: RemoteTask = try await APIClient.shared.request(
                    .taskById(remoteId), method: "PATCH", body: body
                )
                try DatabaseManager.shared.updateSyncStatus(&task, status: .synced)
            } catch {
                print("Failed to update task \(task.title): \(error)")
            }
        }
    }

    // MARK: - Pull Remote Changes (LWW)

    private func pullRemoteProjects() async throws {
        let remoteProjects: [RemoteProject] = try await APIClient.shared.request(.projects)

        for remote in remoteProjects {
            try DatabaseManager.shared.upsertProjectFromRemote(
                remoteId: remote.id,
                name: remote.name,
                createdAt: remote.createdAt
            )
        }
    }

    private func pullRemoteTasks() async throws {
        let remoteTasks: [RemoteTask] = try await APIClient.shared.request(.tasks)

        for remote in remoteTasks {
            try DatabaseManager.shared.upsertTaskFromRemote(
                remoteId: remote.id,
                title: remote.title,
                priority: remote.priority,
                status: remote.status,
                estimateMinutes: remote.estimateMinutes,
                dueDate: remote.dueDate,
                sortOrder: remote.sortOrder,
                createdAt: remote.createdAt,
                updatedAt: remote.updatedAt
            )
        }
    }

    // MARK: - Session Sync

    func syncSession(_ session: Session) {
        guard isOnline, AuthManager.shared.isAuthenticated else { return }
        Task {
            await uploadSession(session)
        }
    }

    func syncSessionEvents(_ session: Session) {
        guard isOnline, AuthManager.shared.isAuthenticated else { return }
        Task {
            await uploadPendingSessionEvents(for: session)
        }
    }

    func syncSessionComplete(_ session: Session) {
        guard isOnline, AuthManager.shared.isAuthenticated else { return }
        Task {
            // Upload final session state
            await uploadSession(session)
            // Upload all remaining events
            await uploadPendingSessionEvents(for: session)
        }
    }

    private func uploadSession(_ session: Session) async {
        var mutableSession = session

        if session.remoteId == nil {
            // Create on server
            let body = SessionUploadBody(
                startTime: session.startTime,
                endTime: session.endTime,
                durationSeconds: session.durationSeconds,
                focusedSeconds: session.focusedSeconds,
                distractionCount: session.distractionCount,
                isComplete: session.isComplete
            )
            do {
                let remote: RemoteSession = try await APIClient.shared.request(
                    .sessions, method: "POST", body: body
                )
                try DatabaseManager.shared.updateSyncStatus(
                    &mutableSession, status: .synced, remoteId: remote.id
                )
            } catch {
                print("Failed to upload session: \(error)")
            }
        } else if let remoteId = session.remoteId {
            // Update on server
            let body = SessionUpdateBody(
                endTime: session.endTime,
                durationSeconds: session.durationSeconds,
                focusedSeconds: session.focusedSeconds,
                distractionCount: session.distractionCount,
                isComplete: session.isComplete
            )
            do {
                let _: RemoteSession = try await APIClient.shared.request(
                    .sessionById(remoteId), method: "PATCH", body: body
                )
                try DatabaseManager.shared.updateSyncStatus(&mutableSession, status: .synced)
            } catch {
                print("Failed to update session: \(error)")
            }
        }
    }

    private func uploadPendingSessionEvents(for session: Session) async {
        guard let remoteSessionId = session.remoteId else { return }
        guard let sessionId = session.id else { return }

        do {
            let events = try DatabaseManager.shared.fetchEvents(sessionId: sessionId)
                .filter { $0.syncStatus != .synced }

            guard !events.isEmpty else { return }

            let eventBodies = events.map { event in
                EventUploadBody(
                    eventType: event.eventType.rawValue,
                    timestamp: event.timestamp,
                    appName: event.appName,
                    durationSeconds: event.durationSeconds
                )
            }

            let batch = EventBatchBody(events: eventBodies)
            let _: [RemoteEvent] = try await APIClient.shared.request(
                .sessionEvents(remoteSessionId), method: "POST", body: batch
            )

            // Mark all as synced
            for var event in events {
                try DatabaseManager.shared.updateSyncStatus(&event, status: .synced)
            }
        } catch {
            print("Failed to upload session events: \(error)")
        }
    }

    // MARK: - Full Reconciliation (24h)

    func fullReconciliation() async {
        await performSync()
    }
}

// MARK: - Remote DTOs

private struct RemoteProject: Codable {
    let id: UUID
    let name: String
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

private struct RemoteTask: Codable {
    let id: UUID
    let title: String
    let priority: Int
    let status: Int
    let estimateMinutes: Int?
    let dueDate: Date?
    let sortOrder: Int
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title, priority, status
        case estimateMinutes = "estimate_minutes"
        case dueDate = "due_date"
        case sortOrder = "sort_order"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

private struct TaskUploadBody: Codable {
    let title: String
    let priority: Int
    let status: Int
    let estimateMinutes: Int?
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case title, priority, status
        case estimateMinutes = "estimate_minutes"
        case sortOrder = "sort_order"
    }
}

private struct RemoteSession: Codable {
    let id: UUID
    let startTime: Date
    let endTime: Date?
    let durationSeconds: Int
    let focusedSeconds: Int
    let distractionCount: Int
    let isComplete: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case startTime = "start_time"
        case endTime = "end_time"
        case durationSeconds = "duration_seconds"
        case focusedSeconds = "focused_seconds"
        case distractionCount = "distraction_count"
        case isComplete = "is_complete"
    }
}

private struct SessionUploadBody: Codable {
    let startTime: Date
    let endTime: Date?
    let durationSeconds: Int
    let focusedSeconds: Int
    let distractionCount: Int
    let isComplete: Bool

    enum CodingKeys: String, CodingKey {
        case startTime = "start_time"
        case endTime = "end_time"
        case durationSeconds = "duration_seconds"
        case focusedSeconds = "focused_seconds"
        case distractionCount = "distraction_count"
        case isComplete = "is_complete"
    }
}

private struct SessionUpdateBody: Codable {
    let endTime: Date?
    let durationSeconds: Int
    let focusedSeconds: Int
    let distractionCount: Int
    let isComplete: Bool

    enum CodingKeys: String, CodingKey {
        case endTime = "end_time"
        case durationSeconds = "duration_seconds"
        case focusedSeconds = "focused_seconds"
        case distractionCount = "distraction_count"
        case isComplete = "is_complete"
    }
}

private struct EventUploadBody: Codable {
    let eventType: String
    let timestamp: Date

    let appName: String?
    let durationSeconds: Int?

    enum CodingKeys: String, CodingKey {
        case eventType = "event_type"
        case timestamp
        case appName = "app_name"
        case durationSeconds = "duration_seconds"
    }
}

private struct EventBatchBody: Codable {
    let events: [EventUploadBody]
}

private struct RemoteEvent: Codable {
    let id: UUID
    let eventType: String
    let timestamp: Date

    enum CodingKeys: String, CodingKey {
        case id
        case eventType = "event_type"
        case timestamp
    }
}
