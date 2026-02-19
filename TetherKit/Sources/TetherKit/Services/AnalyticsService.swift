import CryptoKit
import Foundation
import TelemetryDeck

public enum AnalyticsEvent: String, Sendable {
    case appLaunched
    case sessionStarted
    case sessionEnded
    case taskCreated
    case taskCompleted
    case friendInvited
    case friendAccepted
    case blocklistItemAdded
    case onboardingStepCompleted
    case subscriptionStarted
    case subscriptionCancelled
    case paywallShown
    case brainDumpSubmitted
    case coachMessageSent
    case settingsChanged
}

@MainActor
public final class AnalyticsService: Sendable {
    public static let shared = AnalyticsService()

    private var isInitialized = false

    private init() {}

    public func initialize(appID: String) {
        guard !isInitialized else { return }
        let config = TelemetryDeck.Config(appID: appID)
        TelemetryDeck.initialize(config: config)
        isInitialized = true
    }

    public func identify(userID: String) {
        // Hash the user ID for privacy — no PII sent
        let hashed = SHA256.hash(data: Data(userID.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        TelemetryDeck.updateDefaultUserID(to: hashed)
    }

    public func track(_ event: AnalyticsEvent, parameters: [String: String] = [:]) {
        guard isInitialized else { return }
        TelemetryDeck.signal(event.rawValue, parameters: parameters)
    }

    public func trackOnboardingStep(_ step: Int, name: String) {
        track(.onboardingStepCompleted, parameters: [
            "step": "\(step)",
            "stepName": name,
        ])
    }

    public func trackSessionMetrics(durationSeconds: Int, distractionCount: Int, tasksCompleted: Int) {
        track(.sessionEnded, parameters: [
            "durationMinutes": "\(durationSeconds / 60)",
            "distractions": "\(distractionCount)",
            "tasksCompleted": "\(tasksCompleted)",
        ])
    }
}
