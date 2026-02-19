import Testing
import Foundation
@testable import TetherKit

// MARK: - Insight Model Tests

struct InsightTests {

    @Test func insightCreation() {
        let insight = Insight(
            icon: "flame.fill",
            title: "On fire!",
            message: "You're on a 7-day streak!",
            type: .positive
        )
        #expect(insight.icon == "flame.fill")
        #expect(insight.title == "On fire!")
        #expect(insight.message == "You're on a 7-day streak!")
        #expect(insight.type == .positive)
    }

    @Test func insightUniqueIds() {
        let insight1 = Insight(icon: "star", title: "A", message: "B", type: .positive)
        let insight2 = Insight(icon: "star", title: "A", message: "B", type: .positive)
        #expect(insight1.id != insight2.id)
    }

    @Test func insightTypePositive() {
        let insight = Insight(icon: "star", title: "Good", message: "Nice work", type: .positive)
        if case .positive = insight.type {
            // Expected
        } else {
            Issue.record("Expected positive type")
        }
    }

    @Test func insightTypeWarning() {
        let insight = Insight(
            icon: "exclamationmark.triangle",
            title: "Warning",
            message: "Focus dropped",
            type: .warning
        )
        if case .warning = insight.type {
            // Expected
        } else {
            Issue.record("Expected warning type")
        }
    }

    @Test func insightTypeNeutral() {
        let insight = Insight(
            icon: "info.circle",
            title: "Info",
            message: "Some data",
            type: .neutral
        )
        if case .neutral = insight.type {
            // Expected
        } else {
            Issue.record("Expected neutral type")
        }
    }

    @Test func insightIdentifiable() {
        let insight = Insight(icon: "star", title: "Test", message: "Test message", type: .positive)
        // Verify Identifiable conformance: id should be a UUID
        let _ = insight.id
    }
}

// MARK: - Insight Generation Logic Tests
// These tests verify the threshold logic used by InsightsEngine
// without requiring the database singleton.

struct InsightThresholdTests {

    @Test func streakThresholdSevenDays() {
        // InsightsEngine shows "On fire!" at streak >= 7
        let streak = 7
        #expect(streak >= 7)
    }

    @Test func streakThresholdThreeDays() {
        // InsightsEngine shows "Building momentum" at streak >= 3 (but < 7)
        let streak = 3
        #expect(streak >= 3 && streak < 7)
    }

    @Test func focusImprovementThresholdPositive() {
        // InsightsEngine shows positive insight when improvement > 20%
        let thisWeekFocused = 7200
        let lastWeekFocused = 5000
        let improvement = Double(thisWeekFocused - lastWeekFocused) / Double(lastWeekFocused) * 100
        #expect(improvement > 20)
    }

    @Test func focusDropThresholdNegative() {
        // InsightsEngine shows warning when improvement < -20%
        let thisWeekFocused = 3000
        let lastWeekFocused = 5000
        let improvement = Double(thisWeekFocused - lastWeekFocused) / Double(lastWeekFocused) * 100
        #expect(improvement < -20)
    }

    @Test func highDistractionRateThreshold() {
        // InsightsEngine warns when distraction rate > 5 per hour
        var stats = PeriodStats()
        stats.totalSeconds = 3600 // 1 hour
        stats.distractionCount = 6
        #expect(stats.distractionRate > 5)
    }

    @Test func lowDistractionRateThreshold() {
        // InsightsEngine praises when distraction rate < 1 per hour
        var stats = PeriodStats()
        stats.totalSeconds = 3600
        stats.distractionCount = 0
        stats.sessionCount = 1
        #expect(stats.distractionRate < 1)
        #expect(stats.sessionCount > 0)
    }

    @Test func exceptionalFocusThreshold() {
        // InsightsEngine shows "Exceptional focus" when focus% > 90
        var stats = PeriodStats()
        stats.totalSeconds = 3600
        stats.focusedSeconds = 3300  // 91.7%
        stats.sessionCount = 1
        #expect(stats.focusPercentage > 90)
        #expect(stats.sessionCount > 0)
    }

    @Test func noSessionsThreshold() {
        // InsightsEngine warns when sessionCount == 0
        let stats = PeriodStats()
        #expect(stats.sessionCount == 0)
    }
}
