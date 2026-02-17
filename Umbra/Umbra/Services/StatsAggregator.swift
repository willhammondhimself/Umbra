import Foundation
import GRDB

struct PeriodStats {
    var focusedSeconds: Int = 0
    var totalSeconds: Int = 0
    var sessionCount: Int = 0
    var distractionCount: Int = 0
    var tasksCompleted: Int = 0
    var currentStreak: Int = 0

    var averageSessionLength: Int {
        guard sessionCount > 0 else { return 0 }
        return totalSeconds / sessionCount
    }

    var distractionRate: Double {
        guard totalSeconds > 0 else { return 0 }
        return Double(distractionCount) / (Double(totalSeconds) / 3600.0) // per hour
    }

    var focusPercentage: Double {
        guard totalSeconds > 0 else { return 0 }
        return Double(focusedSeconds) / Double(totalSeconds) * 100
    }
}

struct DailyFocusPoint: Identifiable {
    let id = UUID()
    let date: Date
    let focusedMinutes: Int
}

struct DistractorSummary: Identifiable {
    let id = UUID()
    let appName: String
    let count: Int
    let totalSeconds: Int
}

@MainActor
struct StatsAggregator {

    func stats(from startDate: Date, to endDate: Date) throws -> PeriodStats {
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

    func dailyFocusData(from startDate: Date, to endDate: Date) throws -> [DailyFocusPoint] {
        let db = DatabaseManager.shared.dbQueue
        return try db.read { db in
            let sessions = try Session
                .filter(Column("isComplete") == true)
                .filter(Column("startTime") >= startDate)
                .filter(Column("startTime") <= endDate)
                .fetchAll(db)

            let calendar = Calendar.current
            var dailyMap: [Date: Int] = [:]

            // Initialize all days in range
            var current = calendar.startOfDay(for: startDate)
            let end = calendar.startOfDay(for: endDate)
            while current <= end {
                dailyMap[current] = 0
                current = calendar.date(byAdding: .day, value: 1, to: current)!
            }

            // Aggregate
            for session in sessions {
                let day = calendar.startOfDay(for: session.startTime)
                dailyMap[day, default: 0] += session.focusedSeconds / 60
            }

            return dailyMap
                .sorted { $0.key < $1.key }
                .map { DailyFocusPoint(date: $0.key, focusedMinutes: $0.value) }
        }
    }

    func topDistractors(from startDate: Date, to endDate: Date, limit: Int = 10) throws -> [DistractorSummary] {
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

        // Get all session dates, ordered descending
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
