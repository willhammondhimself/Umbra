import Foundation

public actor APIClient {
    public static let shared = APIClient()

    private var baseURL: URL { ServerEnvironment.current.baseURL }
    private let session = URLSession.shared
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private var retryCount = 0
    private let maxRetries = 3

    // MARK: - Endpoints

    public enum Endpoint: Sendable {
        case projects
        case tasks
        case taskById(UUID)
        case sessions
        case sessionById(UUID)
        case sessionEvents(UUID)
        case stats(String)
        case friends
        case friendInvite
        case friendInviteLink
        case friendJoinLink(String)
        case friendAccept(UUID)
        case groups
        case createGroup
        case groupLeaderboard(UUID)
        case socialEncourage
        case socialPing
        case authMe
        case authRefresh
        case authRegister
        case authLoginEmail
        case authVerifyEmail(String)
        case authPasswordResetRequest
        case authPasswordResetConfirm
        case subscriptionVerify
        case subscriptionStatus
        case registerDevice
        case unregisterDevice(UUID)
        case accountExport
        case accountDelete
        case sessionSummary(UUID)
        case coachingNudge
        case aiGoals
        case heatmap(Int)
        // Third-party integrations
        case webhooks
        case webhookById(UUID)
        case webhookTest(UUID)
        case integrations
        case integrationById(UUID)
        case todoistImport
        case notionImport
        case tasksParse
        case updateSettings
        // Session reactions & activity feed
        case sessionReactions(UUID)
        case reactToSession(UUID)
        case socialActivity

        public var path: String {
            switch self {
            case .projects: "/projects"
            case .tasks: "/tasks"
            case .taskById(let id): "/tasks/\(id)"
            case .sessions: "/sessions"
            case .sessionById(let id): "/sessions/\(id)"
            case .sessionEvents(let id): "/sessions/\(id)/events"
            case .stats(let period): "/stats?period=\(period)"
            case .friends: "/friends"
            case .friendInvite: "/friends/invite"
            case .friendInviteLink: "/friends/invite-link"
            case .friendJoinLink(let code): "/friends/join/\(code)"
            case .friendAccept(let id): "/friends/\(id)/accept"
            case .groups: "/groups"
            case .createGroup: "/groups"
            case .groupLeaderboard(let id): "/groups/\(id)/leaderboard"
            case .socialEncourage: "/social/encourage"
            case .socialPing: "/social/ping"
            case .authMe: "/auth/me"
            case .authRefresh: "/auth/refresh"
            case .authRegister: "/auth/register"
            case .authLoginEmail: "/auth/login/email"
            case .authVerifyEmail(let token): "/auth/verify-email/\(token)"
            case .authPasswordResetRequest: "/auth/password-reset/request"
            case .authPasswordResetConfirm: "/auth/password-reset/confirm"
            case .subscriptionVerify: "/subscriptions/verify"
            case .subscriptionStatus: "/subscriptions/status"
            case .registerDevice: "/devices/register"
            case .unregisterDevice(let id): "/devices/\(id)"
            case .accountExport: "/auth/account/export"
            case .accountDelete: "/auth/account"
            case .sessionSummary(let id): "/insights/session-summary?session_id=\(id)"
            case .coachingNudge: "/insights/nudge"
            case .aiGoals: "/insights/goals/ai"
            case .heatmap(let days): "/insights/heatmap?days=\(days)"
            case .webhooks: "/webhooks"
            case .webhookById(let id): "/webhooks/\(id)"
            case .webhookTest(let id): "/webhooks/\(id)/test"
            case .integrations: "/integrations"
            case .integrationById(let id): "/integrations/\(id)"
            case .todoistImport: "/integrations/todoist/import"
            case .notionImport: "/integrations/notion/import"
            case .tasksParse: "/tasks/parse"
            case .updateSettings: "/auth/settings"
            case .sessionReactions(let id): "/sessions/\(id)/reactions"
            case .reactToSession(let id): "/sessions/\(id)/react"
            case .socialActivity: "/social/activity"
            }
        }
    }

    // MARK: - Generic Request

    public func request<T: Decodable>(
        _ endpoint: Endpoint,
        method: String = "GET",
        body: (any Encodable)? = nil
    ) async throws -> T {
        let url = baseURL.appendingPathComponent(endpoint.path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Inject auth token
        if let token = await MainActor.run(body: { AuthManager.shared.getAccessToken() }) {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.httpBody = try encoder.encode(AnyEncodable(body))
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        // Handle 401 - try refresh and retry once
        if httpResponse.statusCode == 401 && retryCount == 0 {
            retryCount = 1
            let refreshed = await AuthManager.shared.refreshAccessToken()
            if refreshed {
                retryCount = 0
                return try await self.request(endpoint, method: method, body: body)
            }
            retryCount = 0
            throw APIError.unauthorized
        }
        retryCount = 0

        // Handle rate limiting
        if httpResponse.statusCode == 429 {
            throw APIError.rateLimited
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError(httpResponse.statusCode)
        }

        return try decoder.decode(T.self, from: data)
    }

    // Raw data version for export endpoints
    public func requestRawData(
        _ endpoint: Endpoint,
        method: String = "GET"
    ) async throws -> Data {
        let url = baseURL.appendingPathComponent(endpoint.path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = await MainActor.run(body: { AuthManager.shared.getAccessToken() }) {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        return data
    }

    // Non-decoding version for fire-and-forget
    public func requestVoid(
        _ endpoint: Endpoint,
        method: String = "POST",
        body: (any Encodable)? = nil
    ) async throws {
        let _: EmptyResponse = try await request(endpoint, method: method, body: body)
    }
}

// MARK: - Supporting Types

public enum APIError: Error, LocalizedError, Sendable {
    case invalidResponse
    case unauthorized
    case rateLimited
    case serverError(Int)
    case networkUnavailable

    public var errorDescription: String? {
        switch self {
        case .invalidResponse: "Invalid server response"
        case .unauthorized: "Authentication required"
        case .rateLimited: "Too many requests. Please try again later."
        case .serverError(let code): "Server error (\(code))"
        case .networkUnavailable: "No network connection"
        }
    }
}

private struct EmptyResponse: Decodable {}

private struct AnyEncodable: Encodable {
    private let _encode: @Sendable (Encoder) throws -> Void

    init(_ wrapped: any Encodable & Sendable) {
        let box = UncheckedSendableBox(wrapped)
        self._encode = { encoder in
            try box.value.encode(to: encoder)
        }
    }

    init(_ wrapped: any Encodable) {
        nonisolated(unsafe) let captured = wrapped
        self._encode = { encoder in
            try captured.encode(to: encoder)
        }
    }

    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}

private struct UncheckedSendableBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
