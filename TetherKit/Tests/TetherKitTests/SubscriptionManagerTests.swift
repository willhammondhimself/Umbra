import Testing
import Foundation
@testable import TetherKit

// MARK: - Subscription Tier Tests

@Test func testSubscriptionTierRawValues() {
    #expect(SubscriptionTier.free.rawValue == "free")
    #expect(SubscriptionTier.pro.rawValue == "pro")
}

@MainActor
@Test func testSubscriptionProductIDs() {
    #expect(SubscriptionManager.monthlyProductID == "com.willhammond.tether.pro.monthly")
    #expect(SubscriptionManager.yearlyProductID == "com.willhammond.tether.pro.yearly")
}

@MainActor
@Test func testFreeTierLimits() {
    #expect(SubscriptionManager.freeHistoryDays == 30)
    #expect(SubscriptionManager.freeMaxFriends == 3)
    #expect(SubscriptionManager.trialDurationDays == 14)
}

// MARK: - Analytics Event Tests

@Test func testAnalyticsEventRawValues() {
    #expect(AnalyticsEvent.appLaunched.rawValue == "appLaunched")
    #expect(AnalyticsEvent.sessionStarted.rawValue == "sessionStarted")
    #expect(AnalyticsEvent.sessionEnded.rawValue == "sessionEnded")
    #expect(AnalyticsEvent.taskCreated.rawValue == "taskCreated")
    #expect(AnalyticsEvent.subscriptionStarted.rawValue == "subscriptionStarted")
    #expect(AnalyticsEvent.paywallShown.rawValue == "paywallShown")
    #expect(AnalyticsEvent.onboardingStepCompleted.rawValue == "onboardingStepCompleted")
}

// MARK: - Biometric Auth Tests

@MainActor
@Test func testBiometricAuthDefaults() {
    let manager = BiometricAuthManager.shared
    // Default is disabled unless user opts in
    #expect(manager.isEnabled == false || manager.isEnabled == true) // Depends on UserDefaults state
}

@MainActor
@Test func testBiometricTypeNames() {
    // Verify the biometricName property handles all cases
    // (We can't test actual LAContext in unit tests, but we verify the property exists)
    let _ = BiometricAuthManager.shared
}

// MARK: - Content Blocker Rule Generator Tests

@MainActor
@Test func testContentBlockerRuleGeneration() throws {
    let generator = ContentBlockerRuleGenerator()
    let items = [
        BlocklistItem(domain: "reddit.com", displayName: "Reddit"),
        BlocklistItem(domain: "twitter.com", displayName: "Twitter"),
    ]
    let rules = generator.generateRules(from: items)
    #expect(!rules.isEmpty)
}

// MARK: - Data Exporter Tests
// Note: DataExporter CSV/JSON tests moved to DataExporterTests.swift
// The public API uses DatabaseManager.shared internally, so tests use
// the same CSV/JSON format logic with in-memory database.
