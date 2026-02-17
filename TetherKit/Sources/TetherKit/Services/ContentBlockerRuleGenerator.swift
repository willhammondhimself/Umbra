import Foundation

/// Generates `declarativeNetRequest` rules from BlocklistItem arrays.
/// Output format is compatible with both Safari Web Extension and Chrome Extension.
public struct ContentBlockerRuleGenerator: Sendable {
    public init() {}

    /// A single declarativeNetRequest rule.
    public struct DNRRule: Codable, Sendable {
        public let id: Int
        public let priority: Int
        public let action: Action
        public let condition: Condition

        public struct Action: Codable, Sendable {
            public let type: String
            public let redirect: Redirect?

            public init(type: String, redirect: Redirect? = nil) {
                self.type = type
                self.redirect = redirect
            }
        }

        public struct Redirect: Codable, Sendable {
            public let extensionPath: String?

            enum CodingKeys: String, CodingKey {
                case extensionPath
            }
        }

        public struct Condition: Codable, Sendable {
            public let urlFilter: String
            public let resourceTypes: [String]

            enum CodingKeys: String, CodingKey {
                case urlFilter
                case resourceTypes
            }
        }
    }

    /// Generate rules from blocklist items that have domains.
    public func generateRules(from items: [BlocklistItem]) -> [DNRRule] {
        let domainItems = items.filter { $0.isEnabled && $0.domain != nil }
        return domainItems.enumerated().map { index, item in
            makeRule(id: index + 1, item: item)
        }
    }

    /// Generate JSON data from blocklist items.
    public func generateJSON(from items: [BlocklistItem]) throws -> Data {
        let rules = generateRules(from: items)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(rules)
    }

    private func makeRule(id: Int, item: BlocklistItem) -> DNRRule {
        let domain = item.domain ?? ""
        let urlFilter = "||" + domain

        let actionType: String
        var redirect: DNRRule.Redirect? = nil

        switch item.blockMode {
        case .softWarn:
            actionType = "redirect"
            redirect = DNRRule.Redirect(extensionPath: "/blocked.html?domain=\(domain)")
        case .hardBlock, .timedLock:
            actionType = "block"
        }

        return DNRRule(
            id: id,
            priority: 1,
            action: DNRRule.Action(type: actionType, redirect: redirect),
            condition: DNRRule.Condition(
                urlFilter: urlFilter,
                resourceTypes: ["main_frame"]
            )
        )
    }
}
