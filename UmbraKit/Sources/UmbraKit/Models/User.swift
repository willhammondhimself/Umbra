import Foundation

public struct User: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let email: String
    public var displayName: String?
    public var avatarUrl: String?
    public let createdAt: Date

    public init(
        id: UUID,
        email: String,
        displayName: String? = nil,
        avatarUrl: String? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.avatarUrl = avatarUrl
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case createdAt = "created_at"
    }
}
