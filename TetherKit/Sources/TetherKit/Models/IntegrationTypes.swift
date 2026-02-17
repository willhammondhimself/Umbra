import Foundation

// MARK: - Webhook Types

public struct WebhookCreateRequest: Codable, Sendable {
    public let url: String
    public let events: [String]

    public init(url: String, events: [String]) {
        self.url = url
        self.events = events
    }
}

public struct WebhookResponse: Codable, Identifiable, Sendable {
    public let id: UUID
    public let userId: UUID
    public let url: String
    public let events: [String]
    public let secret: String
    public let isActive: Bool
    public let createdAt: Date
}

public struct WebhookTestResponse: Codable, Sendable {
    public let success: Bool
    public let message: String
}

// MARK: - Integration Types

public struct IntegrationCreateRequest: Codable, Sendable {
    public let provider: String
    public let accessToken: String?

    public init(provider: String, accessToken: String?) {
        self.provider = provider
        self.accessToken = accessToken
    }
}

public struct IntegrationResponse: Codable, Identifiable, Sendable {
    public let id: UUID
    public let userId: UUID
    public let provider: String
    public let isActive: Bool
    public let settingsJson: [String: String]?
    public let createdAt: Date
}

// MARK: - Task Import Types

public struct TaskImportRequest: Codable, Sendable {
    public let projectId: String?

    public init(projectId: String?) {
        self.projectId = projectId
    }
}

public struct TaskImportAPIResponse: Codable, Sendable {
    public let importedCount: Int
    public let tasks: [ImportedTask]

    public struct ImportedTask: Codable, Sendable {
        public let title: String
        public let priority: Int
        public let dueDate: String?
    }
}
