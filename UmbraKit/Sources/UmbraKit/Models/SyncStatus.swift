import Foundation

public enum SyncStatus: Int, Codable, CaseIterable, Sendable {
    case local = 0
    case synced = 1
    case pendingUpload = 2
    case pendingUpdate = 3
    case pendingDelete = 4
    case conflicted = 5
}
