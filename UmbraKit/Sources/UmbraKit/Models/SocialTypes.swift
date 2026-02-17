import Foundation

public struct FriendItem: Identifiable, Codable, Sendable {
    public let id: UUID
    public let userId: UUID
    public let displayName: String?
    public let email: String
    public let status: String
    public let since: Date

    public init(id: UUID, userId: UUID, displayName: String?, email: String, status: String, since: Date) {
        self.id = id
        self.userId = userId
        self.displayName = displayName
        self.email = email
        self.status = status
        self.since = since
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case displayName = "display_name"
        case email, status, since
    }
}

public struct GroupItem: Identifiable, Codable, Sendable {
    public let id: UUID
    public let name: String
    public let createdBy: UUID
    public let createdAt: Date
    public let memberCount: Int

    public init(id: UUID, name: String, createdBy: UUID, createdAt: Date, memberCount: Int) {
        self.id = id
        self.name = name
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.memberCount = memberCount
    }

    enum CodingKeys: String, CodingKey {
        case id, name
        case createdBy = "created_by"
        case createdAt = "created_at"
        case memberCount = "member_count"
    }
}

public struct LeaderboardEntryItem: Identifiable, Codable, Sendable {
    public var id: UUID { userId }
    public let userId: UUID
    public let displayName: String?
    public let focusedSeconds: Int
    public let sessionCount: Int
    public let rank: Int

    public init(userId: UUID, displayName: String?, focusedSeconds: Int, sessionCount: Int, rank: Int) {
        self.userId = userId
        self.displayName = displayName
        self.focusedSeconds = focusedSeconds
        self.sessionCount = sessionCount
        self.rank = rank
    }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case displayName = "display_name"
        case focusedSeconds = "focused_seconds"
        case sessionCount = "session_count"
        case rank
    }
}

public struct InviteResponse: Codable, Sendable {
    public let id: UUID
    public let status: String
}
