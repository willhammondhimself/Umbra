import Foundation

// MARK: - Response Models

public struct SessionSummary: Codable, Sendable {
    public let summary: String
    public let isAiGenerated: Bool

    public init(summary: String, isAiGenerated: Bool) {
        self.summary = summary
        self.isAiGenerated = isAiGenerated
    }
}

public struct CoachingNudge: Codable, Sendable {
    public let nudge: String
    public let isAiGenerated: Bool

    public init(nudge: String, isAiGenerated: Bool) {
        self.nudge = nudge
        self.isAiGenerated = isAiGenerated
    }
}

public struct AIGoal: Codable, Sendable {
    public let goal: String
    public let target: String
    public let reasoning: String

    public init(goal: String, target: String, reasoning: String) {
        self.goal = goal
        self.target = target
        self.reasoning = reasoning
    }
}

public struct AIGoalsResponse: Codable, Sendable {
    public let goals: [AIGoal]
    public let isAiGenerated: Bool

    public init(goals: [AIGoal], isAiGenerated: Bool) {
        self.goals = goals
        self.isAiGenerated = isAiGenerated
    }
}

public struct HeatmapEntry: Codable, Sendable {
    public let hour: Int
    public let dayOfWeek: Int
    public let focusedMinutes: Double

    public init(hour: Int, dayOfWeek: Int, focusedMinutes: Double) {
        self.hour = hour
        self.dayOfWeek = dayOfWeek
        self.focusedMinutes = focusedMinutes
    }
}

// MARK: - AI Coaching Service

public actor AICoachingService {
    public static let shared = AICoachingService()

    private let apiClient = APIClient.shared

    // In-memory cache with timestamps for offline fallback
    private var cachedNudge: (value: CoachingNudge, date: Date)?
    private var cachedGoals: (value: AIGoalsResponse, date: Date)?
    private var cachedSummaries: [UUID: SessionSummary] = [:]
    private var cachedHeatmap: (value: [HeatmapEntry], date: Date)?

    private let cacheDuration: TimeInterval = 15 * 60 // 15 minutes

    private init() {}

    // MARK: - Session Summary

    /// Generates an AI-powered summary for a completed focus session.
    public func getSessionSummary(sessionId: UUID) async throws -> SessionSummary {
        // Check cache first
        if let cached = cachedSummaries[sessionId] {
            return cached
        }

        do {
            let summary: SessionSummary = try await apiClient.request(
                .sessionSummary(sessionId),
                method: "POST"
            )
            cachedSummaries[sessionId] = summary
            return summary
        } catch {
            // Return a fallback summary when offline or on error
            return SessionSummary(
                summary: "Session complete. Review your stats above for details.",
                isAiGenerated: false
            )
        }
    }

    // MARK: - Coaching Nudge

    /// Fetches a coaching nudge based on recent productivity patterns.
    public func getCoachingNudge() async throws -> CoachingNudge {
        // Return cached value if still fresh
        if let cached = cachedNudge,
           Date().timeIntervalSince(cached.date) < cacheDuration {
            return cached.value
        }

        do {
            let nudge: CoachingNudge = try await apiClient.request(.coachingNudge)
            cachedNudge = (nudge, Date())
            return nudge
        } catch {
            // Return cached value regardless of age, or a fallback
            if let cached = cachedNudge {
                return cached.value
            }
            return CoachingNudge(
                nudge: "Start a focus session to build momentum today.",
                isAiGenerated: false
            )
        }
    }

    // MARK: - AI Goals

    /// Fetches AI-generated goal suggestions for the week.
    public func getAIGoals() async throws -> AIGoalsResponse {
        // Return cached value if still fresh
        if let cached = cachedGoals,
           Date().timeIntervalSince(cached.date) < cacheDuration {
            return cached.value
        }

        do {
            let goals: AIGoalsResponse = try await apiClient.request(.aiGoals)
            cachedGoals = (goals, Date())
            return goals
        } catch {
            // Return cached value regardless of age, or a fallback
            if let cached = cachedGoals {
                return cached.value
            }
            return AIGoalsResponse(
                goals: [],
                isAiGenerated: false
            )
        }
    }

    // MARK: - Heatmap

    /// Fetches the focus heatmap data for visualization.
    public func getHeatmap(days: Int = 30) async throws -> [HeatmapEntry] {
        // Return cached value if still fresh
        if let cached = cachedHeatmap,
           Date().timeIntervalSince(cached.date) < cacheDuration {
            return cached.value
        }

        do {
            let heatmap: [HeatmapEntry] = try await apiClient.request(.heatmap(days))
            cachedHeatmap = (heatmap, Date())
            return heatmap
        } catch {
            if let cached = cachedHeatmap {
                return cached.value
            }
            return []
        }
    }

    // MARK: - Cache Management

    /// Clears all cached coaching data.
    public func clearCache() {
        cachedNudge = nil
        cachedGoals = nil
        cachedSummaries.removeAll()
        cachedHeatmap = nil
    }
}
