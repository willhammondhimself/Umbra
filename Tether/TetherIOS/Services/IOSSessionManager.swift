import Foundation
import TetherKit

/// iOS session manager. Timer-based without NSWorkspace app monitoring.
/// Distraction detection limited to app-backgrounding events via scene phase.
@MainActor
@Observable
final class IOSSessionManager {
    static let shared = IOSSessionManager()

    enum State: Equatable {
        case idle
        case running
        case paused
        case summary(Session)
    }

    private(set) var state: State = .idle
    private(set) var currentSession: Session?
    private(set) var elapsedSeconds: Int = 0
    private(set) var focusedSeconds: Int = 0
    private(set) var distractionCount: Int = 0

    private var timerTask: Task<Void, Never>?
    private var clock = ContinuousClock()
    private var sessionStartInstant: ContinuousClock.Instant?
    private var pauseStartInstant: ContinuousClock.Instant?
    private var totalPausedDuration: Duration = .zero
    private var backgroundInstant: ContinuousClock.Instant?

    private init() {}

    // MARK: - Lifecycle

    func startSession() {
        guard state == .idle else { return }

        var session = Session(startTime: Date())
        do {
            try DatabaseManager.shared.saveSession(&session)
        } catch {
            return
        }

        currentSession = session
        elapsedSeconds = 0
        focusedSeconds = 0
        distractionCount = 0
        totalPausedDuration = .zero
        sessionStartInstant = clock.now
        state = .running

        logEvent(.start)
        startTimer()

        // Activate Screen Time blocking if authorized
        ScreenTimeBlockingManager.shared.activate()

        SyncManager.shared.syncSession(session)
    }

    func pauseSession() {
        guard state == .running else { return }
        state = .paused
        pauseStartInstant = clock.now
        logEvent(.pause)
        stopTimer()
    }

    func resumeSession() {
        guard state == .paused, let pauseStart = pauseStartInstant else { return }
        totalPausedDuration += clock.now - pauseStart
        pauseStartInstant = nil
        state = .running
        logEvent(.resume)
        startTimer()
    }

    func stopSession() {
        guard state == .running || state == .paused else { return }
        stopTimer()
        ScreenTimeBlockingManager.shared.deactivate()

        guard var session = currentSession else { return }
        session.endTime = Date()
        session.durationSeconds = elapsedSeconds
        session.focusedSeconds = focusedSeconds
        session.distractionCount = distractionCount
        session.isComplete = true

        do {
            try DatabaseManager.shared.saveSession(&session)
        } catch {
            // Non-critical
        }

        logEvent(.stop)
        state = .summary(session)
        currentSession = session

        SyncManager.shared.syncSessionComplete(session)
    }

    func dismissSummary() {
        state = .idle
        currentSession = nil
        elapsedSeconds = 0
        focusedSeconds = 0
        distractionCount = 0
    }

    // MARK: - Scene Phase Distraction Detection

    func handleScenePhaseChange(isActive: Bool) {
        guard state == .running else { return }

        if !isActive {
            // User left the app — count as distraction
            backgroundInstant = clock.now
            distractionCount += 1
        } else if let bgStart = backgroundInstant {
            // Returned to app
            let duration = Int((clock.now - bgStart) / .seconds(1))
            logEvent(.distraction, appName: "Background", duration: max(1, duration))
            backgroundInstant = nil
        }
    }

    // MARK: - Timer

    private func startTimer() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                self?.tick()
            }
        }
    }

    private func stopTimer() {
        timerTask?.cancel()
        timerTask = nil
    }

    private func tick() {
        guard state == .running, let start = sessionStartInstant else { return }
        let raw = clock.now - start - totalPausedDuration
        elapsedSeconds = max(0, Int(raw / .seconds(1)))
        focusedSeconds = elapsedSeconds // On iOS, focused = elapsed minus background time

        if elapsedSeconds % 30 == 0 {
            persistCurrentState()
        }
    }

    private func persistCurrentState() {
        guard var session = currentSession else { return }
        session.durationSeconds = elapsedSeconds
        session.focusedSeconds = focusedSeconds
        session.distractionCount = distractionCount
        do {
            try DatabaseManager.shared.saveSession(&session)
            currentSession = session
        } catch {
            // Non-critical
        }
    }

    // MARK: - Events

    private func logEvent(_ type: SessionEvent.EventType, appName: String? = nil, duration: Int? = nil) {
        guard let sessionId = currentSession?.id else { return }
        var event = SessionEvent(
            sessionId: sessionId,
            eventType: type,
            appName: appName,
            durationSeconds: duration
        )
        do {
            try DatabaseManager.shared.saveEvent(&event)
        } catch {
            // Non-critical
        }
    }

    // MARK: - Recovery

    func checkForIncompleteSession() {
        do {
            if let incomplete = try DatabaseManager.shared.fetchIncompleteSession() {
                currentSession = incomplete
                state = .summary(incomplete)
                SyncManager.shared.syncSessionEvents(incomplete)
            }
        } catch {
            // Non-critical
        }
    }
}
