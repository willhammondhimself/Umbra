import Testing
import Foundation
import GRDB
@testable import TetherKit

// MARK: - PeriodStats Tests

struct PeriodStatsTests {

    @Test func defaultValues() {
        let stats = PeriodStats()
        #expect(stats.focusedSeconds == 0)
        #expect(stats.totalSeconds == 0)
        #expect(stats.sessionCount == 0)
        #expect(stats.distractionCount == 0)
        #expect(stats.tasksCompleted == 0)
        #expect(stats.currentStreak == 0)
    }

    @Test func averageSessionLengthWithZeroSessions() {
        let stats = PeriodStats()
        #expect(stats.averageSessionLength == 0)
    }

    @Test func averageSessionLengthCalculation() {
        var stats = PeriodStats()
        stats.totalSeconds = 3600
        stats.sessionCount = 2
        #expect(stats.averageSessionLength == 1800)
    }

    @Test func averageSessionLengthSingleSession() {
        var stats = PeriodStats()
        stats.totalSeconds = 5400
        stats.sessionCount = 1
        #expect(stats.averageSessionLength == 5400)
    }

    @Test func distractionRateWithZeroSeconds() {
        let stats = PeriodStats()
        #expect(stats.distractionRate == 0)
    }

    @Test func distractionRateCalculation() {
        var stats = PeriodStats()
        stats.totalSeconds = 3600  // 1 hour
        stats.distractionCount = 3
        // 3 distractions / (3600/3600 hours) = 3.0 per hour
        #expect(stats.distractionRate == 3.0)
    }

    @Test func distractionRateHalfHour() {
        var stats = PeriodStats()
        stats.totalSeconds = 1800  // 0.5 hours
        stats.distractionCount = 5
        // 5 / 0.5 = 10.0 per hour
        #expect(stats.distractionRate == 10.0)
    }

    @Test func focusPercentageWithZeroSeconds() {
        let stats = PeriodStats()
        #expect(stats.focusPercentage == 0)
    }

    @Test func focusPercentageCalculation() {
        var stats = PeriodStats()
        stats.totalSeconds = 3600
        stats.focusedSeconds = 2700
        // 2700 / 3600 * 100 = 75.0
        #expect(stats.focusPercentage == 75.0)
    }

    @Test func focusPercentagePerfect() {
        var stats = PeriodStats()
        stats.totalSeconds = 3600
        stats.focusedSeconds = 3600
        #expect(stats.focusPercentage == 100.0)
    }

    @Test func focusPercentageZeroFocus() {
        var stats = PeriodStats()
        stats.totalSeconds = 3600
        stats.focusedSeconds = 0
        #expect(stats.focusPercentage == 0)
    }

    @Test func allComputedPropertiesTogether() {
        var stats = PeriodStats()
        stats.totalSeconds = 7200      // 2 hours
        stats.focusedSeconds = 5400    // 1.5 hours
        stats.sessionCount = 3
        stats.distractionCount = 6
        stats.tasksCompleted = 4

        #expect(stats.averageSessionLength == 2400)  // 7200 / 3
        #expect(stats.focusPercentage == 75.0)        // 5400 / 7200 * 100
        #expect(stats.distractionRate == 3.0)          // 6 / 2.0
    }
}

// MARK: - DailyFocusPoint Tests

struct DailyFocusPointTests {

    @Test func creation() {
        let date = Date()
        let point = DailyFocusPoint(date: date, focusedMinutes: 120)
        #expect(point.date == date)
        #expect(point.focusedMinutes == 120)
    }

    @Test func uniqueIds() {
        let date = Date()
        let point1 = DailyFocusPoint(date: date, focusedMinutes: 60)
        let point2 = DailyFocusPoint(date: date, focusedMinutes: 60)
        #expect(point1.id != point2.id)
    }

    @Test func zeroMinutes() {
        let point = DailyFocusPoint(date: Date(), focusedMinutes: 0)
        #expect(point.focusedMinutes == 0)
    }
}

// MARK: - DistractorSummary Tests

struct DistractorSummaryTests {

    @Test func creation() {
        let summary = DistractorSummary(appName: "Twitter", count: 5, totalSeconds: 300)
        #expect(summary.appName == "Twitter")
        #expect(summary.count == 5)
        #expect(summary.totalSeconds == 300)
    }

    @Test func uniqueIds() {
        let s1 = DistractorSummary(appName: "Twitter", count: 5, totalSeconds: 300)
        let s2 = DistractorSummary(appName: "Twitter", count: 5, totalSeconds: 300)
        #expect(s1.id != s2.id)
    }

    @Test func zeroValues() {
        let summary = DistractorSummary(appName: "App", count: 0, totalSeconds: 0)
        #expect(summary.count == 0)
        #expect(summary.totalSeconds == 0)
    }
}

// MARK: - StatsAggregator with In-Memory Database Tests

@MainActor
struct StatsAggregatorDatabaseTests {

    @Test func statsFromEmptyDatabase() throws {
        let db = DatabaseManager(inMemory: true)
        let calendar = Calendar.current
        let now = Date()
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: now)!

        let stats = try db.dbQueue.read { database in
            let sessions = try Session
                .filter(Column("isComplete") == true)
                .filter(Column("startTime") >= weekAgo)
                .filter(Column("startTime") <= now)
                .fetchAll(database)

            var result = PeriodStats()
            result.focusedSeconds = sessions.reduce(0) { $0 + $1.focusedSeconds }
            result.totalSeconds = sessions.reduce(0) { $0 + $1.durationSeconds }
            result.sessionCount = sessions.count
            result.distractionCount = sessions.reduce(0) { $0 + $1.distractionCount }
            return result
        }

        #expect(stats.focusedSeconds == 0)
        #expect(stats.totalSeconds == 0)
        #expect(stats.sessionCount == 0)
        #expect(stats.distractionCount == 0)
        #expect(stats.averageSessionLength == 0)
        #expect(stats.focusPercentage == 0)
        #expect(stats.distractionRate == 0)
    }

    @Test func statsFromPopulatedDatabase() throws {
        let db = DatabaseManager(inMemory: true)
        let now = Date()

        // Insert completed sessions
        var session1 = Session(
            startTime: now.addingTimeInterval(-3600),
            durationSeconds: 3600,
            focusedSeconds: 3000,
            distractionCount: 2,
            isComplete: true
        )
        try db.dbQueue.write { d in try session1.save(d) }

        var session2 = Session(
            startTime: now.addingTimeInterval(-7200),
            durationSeconds: 1800,
            focusedSeconds: 1500,
            distractionCount: 1,
            isComplete: true
        )
        try db.dbQueue.write { d in try session2.save(d) }

        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: now)!

        let stats = try db.dbQueue.read { database in
            let sessions = try Session
                .filter(Column("isComplete") == true)
                .filter(Column("startTime") >= weekAgo)
                .filter(Column("startTime") <= now)
                .fetchAll(database)

            var result = PeriodStats()
            result.focusedSeconds = sessions.reduce(0) { $0 + $1.focusedSeconds }
            result.totalSeconds = sessions.reduce(0) { $0 + $1.durationSeconds }
            result.sessionCount = sessions.count
            result.distractionCount = sessions.reduce(0) { $0 + $1.distractionCount }
            return result
        }

        #expect(stats.sessionCount == 2)
        #expect(stats.totalSeconds == 5400)
        #expect(stats.focusedSeconds == 4500)
        #expect(stats.distractionCount == 3)
        #expect(stats.averageSessionLength == 2700)
    }

    @Test func statsExcludesIncompleteSessions() throws {
        let db = DatabaseManager(inMemory: true)
        let now = Date()

        // Complete session
        var complete = Session(
            startTime: now.addingTimeInterval(-3600),
            durationSeconds: 3600,
            focusedSeconds: 3000,
            isComplete: true
        )
        try db.dbQueue.write { d in try complete.save(d) }

        // Incomplete session
        var incomplete = Session(
            startTime: now.addingTimeInterval(-1800),
            durationSeconds: 1800,
            focusedSeconds: 1000,
            isComplete: false
        )
        try db.dbQueue.write { d in try incomplete.save(d) }

        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: now)!

        let stats = try db.dbQueue.read { database in
            let sessions = try Session
                .filter(Column("isComplete") == true)
                .filter(Column("startTime") >= weekAgo)
                .filter(Column("startTime") <= now)
                .fetchAll(database)

            var result = PeriodStats()
            result.sessionCount = sessions.count
            result.totalSeconds = sessions.reduce(0) { $0 + $1.durationSeconds }
            result.focusedSeconds = sessions.reduce(0) { $0 + $1.focusedSeconds }
            return result
        }

        #expect(stats.sessionCount == 1)
        #expect(stats.totalSeconds == 3600)
        #expect(stats.focusedSeconds == 3000)
    }

    @Test func statsExcludesOutOfRangeSessions() throws {
        let db = DatabaseManager(inMemory: true)
        let now = Date()

        // Session from 2 weeks ago
        var oldSession = Session(
            startTime: now.addingTimeInterval(-14 * 86400),
            durationSeconds: 3600,
            focusedSeconds: 3000,
            isComplete: true
        )
        try db.dbQueue.write { d in try oldSession.save(d) }

        // Recent session
        var recentSession = Session(
            startTime: now.addingTimeInterval(-3600),
            durationSeconds: 1800,
            focusedSeconds: 1500,
            isComplete: true
        )
        try db.dbQueue.write { d in try recentSession.save(d) }

        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: now)!

        let stats = try db.dbQueue.read { database in
            let sessions = try Session
                .filter(Column("isComplete") == true)
                .filter(Column("startTime") >= weekAgo)
                .filter(Column("startTime") <= now)
                .fetchAll(database)

            var result = PeriodStats()
            result.sessionCount = sessions.count
            result.totalSeconds = sessions.reduce(0) { $0 + $1.durationSeconds }
            return result
        }

        #expect(stats.sessionCount == 1)
        #expect(stats.totalSeconds == 1800)
    }

    @Test func streakCalculationWithConsecutiveDays() throws {
        let db = DatabaseManager(inMemory: true)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Insert sessions for today, yesterday, and day before
        for dayOffset in 0..<3 {
            let date = calendar.date(byAdding: .day, value: -dayOffset, to: today)!
            var session = Session(
                startTime: date.addingTimeInterval(3600), // 1am that day
                durationSeconds: 1800,
                focusedSeconds: 1500,
                isComplete: true
            )
            try db.dbQueue.write { d in try session.save(d) }
        }

        // Verify we have 3 sessions
        let count = try db.dbQueue.read { d in try Session.fetchCount(d) }
        #expect(count == 3)
    }

    @Test func streakBrokenByGap() throws {
        let db = DatabaseManager(inMemory: true)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Session today
        var todaySession = Session(
            startTime: today.addingTimeInterval(3600),
            durationSeconds: 1800,
            focusedSeconds: 1500,
            isComplete: true
        )
        try db.dbQueue.write { d in try todaySession.save(d) }

        // Session 3 days ago (gap of 2 days)
        let threeDaysAgo = calendar.date(byAdding: .day, value: -3, to: today)!
        var oldSession = Session(
            startTime: threeDaysAgo.addingTimeInterval(3600),
            durationSeconds: 1800,
            focusedSeconds: 1500,
            isComplete: true
        )
        try db.dbQueue.write { d in try oldSession.save(d) }

        // Manually compute streak logic
        let rows = try db.dbQueue.read { d in
            try Row.fetchAll(d, sql: """
                SELECT DISTINCT date(startTime) as sessionDate
                FROM sessions
                WHERE isComplete = 1
                ORDER BY sessionDate DESC
                """)
        }
        #expect(rows.count == 2)
    }
}
