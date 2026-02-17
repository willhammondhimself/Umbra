import Foundation
import AppKit
import Combine
import UmbraKit

enum SessionState: Equatable {
    case idle
    case running
    case paused
    case summary(Session)
}

@MainActor
@Observable
final class SessionManager {
    static let shared = SessionManager()

    private(set) var state: SessionState = .idle
    private(set) var currentSession: Session?
    private(set) var elapsedSeconds: Int = 0
    private(set) var focusedSeconds: Int = 0
    private(set) var distractionCount: Int = 0
    private(set) var currentApp: String = ""
    private(set) var isDistracted: Bool = false

    private var timerTask: Task<Void, Never>?
    private var sessionStartUptime: TimeInterval = 0
    private var pauseStartUptime: TimeInterval = 0
    private var totalPausedDuration: TimeInterval = 0
    private var distractionStartUptime: TimeInterval?

    private let appMonitor = AppMonitor()
    private var unsentEventCount = 0

    // Blocklist of app bundle IDs considered distractions (populated from BlocklistItems later)
    var distractingBundleIds: Set<String> = []

    // MARK: - Session Lifecycle

    func startSession() {
        guard state == .idle else { return }

        let now = Date()
        var session = Session(startTime: now)

        do {
            try DatabaseManager.shared.saveSession(&session)
        } catch {
            print("Failed to save session: \(error)")
            return
        }

        currentSession = session
        elapsedSeconds = 0
        focusedSeconds = 0
        distractionCount = 0
        totalPausedDuration = 0
        distractionStartUptime = nil
        sessionStartUptime = ProcessInfo.processInfo.systemUptime
        state = .running

        logEvent(.start)
        startTimer()
        appMonitor.startMonitoring { [weak self] appName, bundleId in
            self?.handleAppSwitch(appName: appName, bundleId: bundleId)
        }

        // Activate blocking
        BlockingManager.shared.activate()

        // Show floating widget
        FloatingWidgetController.shared.showWidget()

        // Listen for system sleep/wake
        registerSleepWakeNotifications()

        // Trigger sync to create session on server
        SyncManager.shared.syncSession(session)
    }

    func pauseSession() {
        guard state == .running else { return }
        state = .paused
        pauseStartUptime = ProcessInfo.processInfo.systemUptime
        endDistraction()
        logEvent(.pause)
        stopTimer()
        appMonitor.stopMonitoring()
    }

    func resumeSession() {
        guard state == .paused else { return }
        let pauseDuration = ProcessInfo.processInfo.systemUptime - pauseStartUptime
        totalPausedDuration += pauseDuration
        state = .running
        logEvent(.resume)
        startTimer()
        appMonitor.startMonitoring { [weak self] appName, bundleId in
            self?.handleAppSwitch(appName: appName, bundleId: bundleId)
        }
    }

    func stopSession() {
        guard state == .running || state == .paused else { return }
        endDistraction()
        stopTimer()
        appMonitor.stopMonitoring()
        unregisterSleepWakeNotifications()
        BlockingManager.shared.deactivate()
        FloatingWidgetController.shared.hideWidget()

        guard var session = currentSession else { return }
        session.endTime = Date()
        session.durationSeconds = elapsedSeconds
        session.focusedSeconds = focusedSeconds
        session.distractionCount = distractionCount
        session.isComplete = true

        do {
            try DatabaseManager.shared.saveSession(&session)
        } catch {
            print("Failed to finalize session: \(error)")
        }

        logEvent(.stop)
        state = .summary(session)
        currentSession = session

        // Sync completed session + all remaining events
        SyncManager.shared.syncSessionComplete(session)
    }

    func dismissSummary() {
        state = .idle
        currentSession = nil
        elapsedSeconds = 0
        focusedSeconds = 0
        distractionCount = 0
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
        guard state == .running else { return }
        let uptime = ProcessInfo.processInfo.systemUptime
        let raw = uptime - sessionStartUptime - totalPausedDuration
        elapsedSeconds = max(0, Int(raw))

        if !isDistracted {
            focusedSeconds = elapsedSeconds - totalDistractionSeconds()
        }

        // Update current session in DB periodically (every 30s)
        if elapsedSeconds % 30 == 0 {
            persistCurrentState()
        }
    }

    private func totalDistractionSeconds() -> Int {
        guard let session = currentSession, let sessionId = session.id else { return 0 }
        do {
            let events = try DatabaseManager.shared.fetchEvents(sessionId: sessionId)
            return events
                .filter { $0.eventType == .distraction }
                .compactMap { $0.durationSeconds }
                .reduce(0, +)
        } catch {
            return 0
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
            print("Failed to persist session state: \(error)")
        }
    }

    // MARK: - App Monitoring

    private func handleAppSwitch(appName: String, bundleId: String) {
        currentApp = appName
        let isUmbra = bundleId == Bundle.main.bundleIdentifier
        let isExempted = BlockingManager.shared.sessionExemptions.contains(bundleId)

        if !isUmbra && !isExempted && !appMonitor.isIdle {
            endDistraction()          // flush previous distraction event if switching apps
            startDistraction(appName: appName)
        } else {
            endDistraction()
        }
    }

    private func startDistraction(appName: String) {
        guard !isDistracted else { return }
        isDistracted = true
        distractionStartUptime = ProcessInfo.processInfo.systemUptime
        distractionCount += 1
    }

    private func endDistraction() {
        guard isDistracted, let startUptime = distractionStartUptime else { return }
        isDistracted = false
        let duration = Int(ProcessInfo.processInfo.systemUptime - startUptime)
        distractionStartUptime = nil

        logEvent(.distraction, appName: currentApp, duration: max(1, duration))
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
            unsentEventCount += 1

            // Flush events to server when 10+ buffered
            if unsentEventCount >= 10, let session = currentSession {
                unsentEventCount = 0
                SyncManager.shared.syncSessionEvents(session)
            }
        } catch {
            print("Failed to log event: \(error)")
        }
    }

    // MARK: - Sleep/Wake

    private func registerSleepWakeNotifications() {
        let wsnc = NSWorkspace.shared.notificationCenter
        wsnc.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            if self?.state == .running {
                self?.pauseSession()
            }
        }
        wsnc.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Session remains paused after wake; user must manually resume
        }
    }

    private func unregisterSleepWakeNotifications() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    // MARK: - Recovery

    func checkForIncompleteSession() {
        do {
            if let incomplete = try DatabaseManager.shared.fetchIncompleteSession() {
                // Offer to resume or discard
                currentSession = incomplete
                state = .summary(incomplete) // Show as summary so user can see what happened

                // Sync any unsent events from the crashed session
                SyncManager.shared.syncSessionEvents(incomplete)
            }
        } catch {
            print("Failed to check for incomplete sessions: \(error)")
        }
    }
}
