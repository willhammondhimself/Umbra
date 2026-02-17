import Foundation

public struct Insight: Identifiable, Sendable {
    public let id = UUID()
    public let icon: String
    public let title: String
    public let message: String
    public let type: InsightType

    public enum InsightType: Sendable {
        case positive
        case warning
        case neutral
    }

    public init(icon: String, title: String, message: String, type: InsightType) {
        self.icon = icon
        self.title = title
        self.message = message
        self.type = type
    }
}

@MainActor
public struct InsightsEngine {
    private let aggregator = StatsAggregator()

    public init() {}

    public func generateInsights() -> [Insight] {
        var insights: [Insight] = []
        let calendar = Calendar.current
        let now = Date()

        guard let weekStart = calendar.date(byAdding: .day, value: -7, to: now),
              let prevWeekStart = calendar.date(byAdding: .day, value: -14, to: now) else {
            return insights
        }

        guard let thisWeek = try? aggregator.stats(from: weekStart, to: now),
              let lastWeek = try? aggregator.stats(from: prevWeekStart, to: weekStart) else {
            return insights
        }

        if thisWeek.currentStreak >= 7 {
            insights.append(Insight(
                icon: "flame.fill",
                title: "On fire!",
                message: "You're on a \(thisWeek.currentStreak)-day streak. Keep it up!",
                type: .positive
            ))
        } else if thisWeek.currentStreak >= 3 {
            insights.append(Insight(
                icon: "flame",
                title: "Building momentum",
                message: "\(thisWeek.currentStreak) days in a row. You're building a great habit.",
                type: .positive
            ))
        }

        if lastWeek.focusedSeconds > 0 {
            let improvement = Double(thisWeek.focusedSeconds - lastWeek.focusedSeconds) / Double(lastWeek.focusedSeconds) * 100
            if improvement > 20 {
                insights.append(Insight(
                    icon: "arrow.up.right",
                    title: "Focus time up!",
                    message: String(format: "%.0f%% more focused time than last week.", improvement),
                    type: .positive
                ))
            } else if improvement < -20 {
                insights.append(Insight(
                    icon: "arrow.down.right",
                    title: "Focus time dropped",
                    message: String(format: "%.0f%% less focused time than last week. Schedule some sessions!", abs(improvement)),
                    type: .warning
                ))
            }
        }

        if thisWeek.distractionRate > 5 {
            insights.append(Insight(
                icon: "exclamationmark.triangle",
                title: "High distraction rate",
                message: String(format: "%.1f distractions per hour this week. Consider blocking more apps.", thisWeek.distractionRate),
                type: .warning
            ))
        } else if thisWeek.sessionCount > 0 && thisWeek.distractionRate < 1 {
            insights.append(Insight(
                icon: "checkmark.shield",
                title: "Laser focused",
                message: "Less than 1 distraction per hour. Outstanding focus!",
                type: .positive
            ))
        }

        if thisWeek.sessionCount == 0 {
            insights.append(Insight(
                icon: "calendar.badge.exclamationmark",
                title: "No sessions this week",
                message: "Start a focus session to get back on track.",
                type: .warning
            ))
        }

        if thisWeek.focusPercentage > 90 && thisWeek.sessionCount > 0 {
            insights.append(Insight(
                icon: "star.fill",
                title: "Exceptional focus",
                message: String(format: "%.0f%% focus rate this week. You're in the zone!", thisWeek.focusPercentage),
                type: .positive
            ))
        }

        if let distractors = try? aggregator.topDistractors(from: weekStart, to: now, limit: 1),
           let top = distractors.first, top.count >= 5 {
            insights.append(Insight(
                icon: "app.badge",
                title: "Top distractor: \(top.appName)",
                message: "\(top.count) times this week (\(top.totalSeconds / 60) min lost). Consider adding to blocklist.",
                type: .neutral
            ))
        }

        return insights
    }
}
