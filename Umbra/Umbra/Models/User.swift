import Foundation

struct User: Identifiable, Codable, Equatable {
    let id: UUID
    let email: String
    var displayName: String?
    var avatarUrl: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case createdAt = "created_at"
    }
}
