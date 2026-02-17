import Foundation

actor APIClient {
    static let shared = APIClient()

    private let baseURL = URL(string: "http://localhost:8000")!
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

    enum Endpoint {
        case projects
        case tasks
        case taskById(UUID)
        case sessions
        case sessionById(UUID)
        case sessionEvents(UUID)
        case stats(String)
        case friends
        case friendInvite
        case friendAccept(UUID)
        case groups
        case groupLeaderboard(UUID)
        case socialEncourage
        case socialPing
        case authMe
        case authRefresh

        var path: String {
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
            case .friendAccept(let id): "/friends/\(id)/accept"
            case .groups: "/groups"
            case .groupLeaderboard(let id): "/groups/\(id)/leaderboard"
            case .socialEncourage: "/social/encourage"
            case .socialPing: "/social/ping"
            case .authMe: "/auth/me"
            case .authRefresh: "/auth/refresh"
            }
        }
    }

    // MARK: - Generic Request

    func request<T: Decodable>(
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

    // Non-decoding version for fire-and-forget
    func requestVoid(
        _ endpoint: Endpoint,
        method: String = "POST",
        body: (any Encodable)? = nil
    ) async throws {
        let _: EmptyResponse = try await request(endpoint, method: method, body: body)
    }
}

// MARK: - Supporting Types

enum APIError: Error, LocalizedError {
    case invalidResponse
    case unauthorized
    case rateLimited
    case serverError(Int)
    case networkUnavailable

    var errorDescription: String? {
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
    private let encode: (Encoder) throws -> Void

    init(_ wrapped: any Encodable) {
        self.encode = wrapped.encode(to:)
    }

    func encode(to encoder: Encoder) throws {
        try encode(encoder)
    }
}
