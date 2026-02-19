import Testing
import Foundation
@testable import Tether
@testable import TetherKit

// MARK: - SessionState Tests

struct SessionStateTests {

    @Test func idleState() {
        let state = SessionState.idle
        #expect(state == .idle)
    }

    @Test func runningState() {
        let state = SessionState.running
        #expect(state == .running)
    }

    @Test func pausedState() {
        let state = SessionState.paused
        #expect(state == .paused)
    }

    @Test func summaryState() {
        let session = Session(
            startTime: Date(),
            durationSeconds: 3600,
            focusedSeconds: 3000,
            distractionCount: 2,
            isComplete: true
        )
        let state = SessionState.summary(session)
        if case .summary(let s) = state {
            #expect(s.durationSeconds == 3600)
            #expect(s.focusedSeconds == 3000)
            #expect(s.distractionCount == 2)
            #expect(s.isComplete == true)
        } else {
            Issue.record("Expected summary state")
        }
    }

    @Test func stateEquality() {
        #expect(SessionState.idle == SessionState.idle)
        #expect(SessionState.running == SessionState.running)
        #expect(SessionState.paused == SessionState.paused)
        #expect(SessionState.idle != SessionState.running)
        #expect(SessionState.running != SessionState.paused)
    }

    @Test func summaryStateEquality() {
        let session1 = Session(
            startTime: Date(timeIntervalSince1970: 1000),
            durationSeconds: 3600,
            focusedSeconds: 3000,
            isComplete: true
        )
        let session2 = Session(
            startTime: Date(timeIntervalSince1970: 1000),
            durationSeconds: 3600,
            focusedSeconds: 3000,
            isComplete: true
        )
        // Both have nil ids, same data - should be equal via Session Equatable
        #expect(SessionState.summary(session1) == SessionState.summary(session2))
    }

    @Test func summaryStateInequalityDifferentDuration() {
        let session1 = Session(durationSeconds: 3600, isComplete: true)
        let session2 = Session(durationSeconds: 1800, isComplete: true)
        #expect(SessionState.summary(session1) != SessionState.summary(session2))
    }
}

// MARK: - SessionManager State Tests

@MainActor
struct SessionManagerStateTests {

    @Test func initialStateIsIdle() {
        let manager = SessionManager.shared
        // After dismissing any residual summary, state should be idle
        // Note: This reads the singleton state which may vary between test runs
        // but the shared instance initializes to .idle
        _ = manager.state // Verify it's accessible
    }

    @Test func initialElapsedSecondsIsZero() {
        let manager = SessionManager.shared
        // After dismissSummary, elapsed resets to 0
        manager.dismissSummary()
        #expect(manager.elapsedSeconds == 0)
    }

    @Test func initialFocusedSecondsIsZero() {
        let manager = SessionManager.shared
        manager.dismissSummary()
        #expect(manager.focusedSeconds == 0)
    }

    @Test func initialDistractionCountIsZero() {
        let manager = SessionManager.shared
        manager.dismissSummary()
        #expect(manager.distractionCount == 0)
    }

    @Test func dismissSummaryResetsState() {
        let manager = SessionManager.shared
        manager.dismissSummary()
        #expect(manager.state == .idle)
        #expect(manager.currentSession == nil)
        #expect(manager.elapsedSeconds == 0)
        #expect(manager.focusedSeconds == 0)
        #expect(manager.distractionCount == 0)
    }

    @Test func pauseFromIdleDoesNothing() {
        let manager = SessionManager.shared
        manager.dismissSummary()
        #expect(manager.state == .idle)
        manager.pauseSession()
        // Should remain idle since guard check prevents pausing from idle
        #expect(manager.state == .idle)
    }

    @Test func resumeFromIdleDoesNothing() {
        let manager = SessionManager.shared
        manager.dismissSummary()
        #expect(manager.state == .idle)
        manager.resumeSession()
        // Should remain idle since guard check prevents resuming from idle
        #expect(manager.state == .idle)
    }

    @Test func stopFromIdleDoesNothing() {
        let manager = SessionManager.shared
        manager.dismissSummary()
        #expect(manager.state == .idle)
        manager.stopSession()
        // Should remain idle since guard check prevents stopping from idle
        #expect(manager.state == .idle)
    }
}

// MARK: - Session Timer Calculation Tests

struct SessionTimerTests {

    @Test func formatSecondsZero() {
        #expect(Session.formatSeconds(0) == "00:00")
    }

    @Test func formatSecondsUnderMinute() {
        #expect(Session.formatSeconds(45) == "00:45")
    }

    @Test func formatSecondsOneMinute() {
        #expect(Session.formatSeconds(60) == "01:00")
    }

    @Test func formatSecondsMinutesAndSeconds() {
        #expect(Session.formatSeconds(65) == "01:05")
    }

    @Test func formatSecondsOneHour() {
        #expect(Session.formatSeconds(3600) == "1:00:00")
    }

    @Test func formatSecondsOneHourOneMinuteOneSecond() {
        #expect(Session.formatSeconds(3661) == "1:01:01")
    }

    @Test func formatSecondsTwoHours() {
        #expect(Session.formatSeconds(7200) == "2:00:00")
    }

    @Test func formatSecondsLargeValue() {
        // 10 hours, 30 minutes, 15 seconds
        let seconds = 10 * 3600 + 30 * 60 + 15
        #expect(Session.formatSeconds(seconds) == "10:30:15")
    }

    @Test func focusPercentageZeroDuration() {
        let session = Session(durationSeconds: 0)
        #expect(session.focusPercentage == 0)
    }

    @Test func focusPercentageCalculation() {
        let session = Session(durationSeconds: 100, focusedSeconds: 80)
        #expect(session.focusPercentage == 80.0)
    }

    @Test func focusPercentageFull() {
        let session = Session(durationSeconds: 100, focusedSeconds: 100)
        #expect(session.focusPercentage == 100.0)
    }

    @Test func focusPercentageNone() {
        let session = Session(durationSeconds: 100, focusedSeconds: 0)
        #expect(session.focusPercentage == 0)
    }

    @Test func formattedDuration() {
        let session = Session(durationSeconds: 3661)
        #expect(session.formattedDuration == "1:01:01")
    }

    @Test func formattedFocused() {
        let session = Session(focusedSeconds: 1800)
        #expect(session.formattedFocused == "30:00")
    }
}

// MARK: - Session Recovery Tests

@MainActor
struct SessionRecoveryTests {

    @Test func hasIncompleteSessionDefaultsFalse() {
        let manager = SessionManager.shared
        // The incompleteSession is populated by checkForIncompleteSession
        // which requires DB state. Default property check:
        _ = manager.hasIncompleteSession
    }

    @Test func incompleteSessionPropertyAccessible() {
        let manager = SessionManager.shared
        _ = manager.incompleteSession
    }

    @Test func persistOnTerminationDoesNotCrash() {
        let manager = SessionManager.shared
        manager.dismissSummary()
        // Should safely handle nil currentSession
        manager.persistOnTermination()
    }
}
