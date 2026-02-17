import Foundation

/// Reads/writes blocklist rules to a shared UserDefaults suite for communication
/// between the main app and the Safari Web Extension via app group container.
public final class SharedBlocklistStore: Sendable {
    public static let shared = SharedBlocklistStore()

    private let suiteName = "group.com.tether.shared"
    private let rulesKey = "safari_blocklist_rules"
    private let sessionActiveKey = "is_session_active"
    private let lastUpdatedKey = "blocklist_last_updated"

    /// Darwin notification name posted when rules change.
    public static let rulesDidChangeNotification = "com.tether.blocklist.updated"

    private var defaults: UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }

    public init() {}

    // MARK: - Rules

    /// Write generated DNR rules JSON to the shared container.
    public func writeRules(_ items: [BlocklistItem]) {
        let generator = ContentBlockerRuleGenerator()
        guard let json = try? generator.generateJSON(from: items) else { return }
        defaults?.set(json, forKey: rulesKey)
        defaults?.set(Date().timeIntervalSince1970, forKey: lastUpdatedKey)
        postDarwinNotification()
    }

    /// Read rules JSON from the shared container.
    public func readRulesJSON() -> Data? {
        defaults?.data(forKey: rulesKey)
    }

    /// Read rules as decoded DNR rule objects.
    public func readRules() -> [ContentBlockerRuleGenerator.DNRRule] {
        guard let data = readRulesJSON() else { return [] }
        return (try? JSONDecoder().decode([ContentBlockerRuleGenerator.DNRRule].self, from: data)) ?? []
    }

    // MARK: - Session State

    /// Set whether a focus session is currently active.
    public func setSessionActive(_ active: Bool) {
        defaults?.set(active, forKey: sessionActiveKey)
        postDarwinNotification()
    }

    /// Check if a focus session is currently active.
    public func isSessionActive() -> Bool {
        defaults?.bool(forKey: sessionActiveKey) ?? false
    }

    // MARK: - Darwin Notification

    private func postDarwinNotification() {
        let name = SharedBlocklistStore.rulesDidChangeNotification as CFString
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name),
            nil,
            nil,
            true
        )
    }
}
