import Foundation
import GRDB

public struct PeriodStats: Sendable {
    public var focusedSeconds: Int = 0
    public var totalSeconds: Int = 0
    public var sessionCount: Int = 0
    public var distractionCount: Int = 0
    public var tasksCompleted: Int = 0
    public var currentStreak: Int = 0

    public init() {}

    public var averageSessionLength: Int {
        guard sessionCount > 0 else { return 0 }
        return totalSeconds / sessionCount
    }

    public var distractionRate: Double {
        guard totalSeconds > 0 else { return 0 }
        return Double(distractionCount) / (Double(totalSeconds) / 3600.0)
    }

    public var focusPercentage: Double {
        guard totalSeconds > 0 else { return 0 }
        return Double(focusedSeconds) / Double(totalSeconds) * 100
    }
}

public struct DailyFocusPoint: Identifiable, Sendable {
    public let id = UUID()
    public let date: Date
    public let focusedMinutes: Int

    public init(date: Date, focusedMinutes: Int) {
        self.date = date
        self.focusedMinutes = focusedMinutes
    }
}

public struct DistractorSummary: Identifiable, Sendable {
    public let id = UUID()
    public let appName: String
    public let count: Int
    public let totalSeconds: Int

    public init(appName: String, count: Int, totalSeconds: Int) {
        self.appName = appName
        self.count = count
        self.totalSeconds = totalSeconds
    }
}

@MainActor
public struct StatsAggregator {

    public init() {}

    public func stats(from startDate: Date, to endDate: Date) throws -> PeriodStats {
        let db = DatabaseManager.shared.dbQueue
        return try db.read { db in
            let sessions = try Session
                .filter(Column("isComplete") == true)
                .filter(Column("startTime") >= startDate)
                .filter(Column("startTime") <= endDate)
                .fetchAll(db)

            let tasks = try UmbraTask
                .filter(Column("status") == UmbraTask.Status.done.rawValue)
                .filter(Column("updatedAt") >= startDate)
                .filter(Column("updatedAt") <= endDate)
                .fetchAll(db)

            var result = PeriodStats()
            result.focusedSeconds = sessions.reduce(0) { $0 + $1.focusedSeconds }
            result.totalSeconds = sessions.reduce(0) { $0 + $1.durationSeconds }
            result.sessionCount = sessions.count
            result.distractionCount = sessions.reduce(0) { $0 + $1.distractionCount }
            result.tasksCompleted = tasks.count
            result.currentStreak = try calculateStreak(db: db)

            return result
        }
    }

    public func dailyFocusData(from startDate: Date, to endDate: Date) throws -> [DailyFocusPoint] {
        let db = DatabaseManager.shared.dbQueue
        return try db.read { db in
            let sessions = try Session
                .filter(Column("isComplete") == true)
                .filter(Column("startTime") >= startDate)
                .filter(Column("startTime") <= endDate)
                .fetchAll(db)

            let calendar = Calendar.current
            var dailyMap: [Date: Int] = [:]

            var current = calendar.startOfDay(for: startDate)
            let end = calendar.startOfDay(for: endDate)
            while current <= end {
                dailyMap[current] = 0
                current = calendar.date(byAdding: .day, value: 1, to: current)!
            }

            for session in sessions {
                let day = calendar.startOfDay(for: session.startTime)
                dailyMap[day, default: 0] += session.focusedSeconds / 60
            }

            return dailyMap
                .sorted { $0.key < $1.key }
                .map { DailyFocusPoint(date: $0.key, focusedMinutes: $0.value) }
        }
    }

    public func topDistractors(from startDate: Date, to endDate: Date, limit: Int = 10) throws -> [DistractorSummary] {
        let db = DatabaseManager.shared.dbQueue
        return try db.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT se.appName, COUNT(*) as count, COALESCE(SUM(se.durationSeconds), 0) as totalSeconds
                FROM session_events se
                JOIN sessions s ON se.sessionId = s.id
                WHERE se.eventType = 'DISTRACTION'
                  AND se.appName IS NOT NULL
                  AND s.startTime >= ?
                  AND s.startTime <= ?
                GROUP BY se.appName
                ORDER BY count DESC
                LIMIT ?
                """, arguments: [startDate, endDate, limit])

            return rows.map { row in
                DistractorSummary(
                    appName: row["appName"],
                    count: row["count"],
                    totalSeconds: row["totalSeconds"]
                )
            }
        }
    }

    private func calculateStreak(db: Database) throws -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let rows = try Row.fetchAll(db, sql: """
            SELECT DISTINCT date(startTime) as sessionDate
            FROM sessions
            WHERE isComplete = 1
            ORDER BY sessionDate DESC
            """)

        var streak = 0
        var expectedDate = today

        for row in rows {
            guard let dateStr: String = row["sessionDate"],
                  let date = Self.dateFormatter.date(from: dateStr) else { continue }

            let sessionDay = calendar.startOfDay(for: date)

            if sessionDay == expectedDate {
                streak += 1
                expectedDate = calendar.date(byAdding: .day, value: -1, to: expectedDate)!
            } else if sessionDay < expectedDate {
                break
            }
        }

        return streak
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
