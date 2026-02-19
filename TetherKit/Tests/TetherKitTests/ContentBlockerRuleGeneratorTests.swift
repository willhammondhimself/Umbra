import Testing
import Foundation
@testable import TetherKit

// MARK: - Content Blocker Rule Generator Tests

struct ContentBlockerRuleGeneratorTests {
    let generator = ContentBlockerRuleGenerator()

    // MARK: - Rule Generation from Domain List

    @Test func generateRulesFromDomainList() {
        let items = [
            BlocklistItem(domain: "reddit.com", displayName: "Reddit"),
            BlocklistItem(domain: "twitter.com", displayName: "Twitter"),
            BlocklistItem(domain: "facebook.com", displayName: "Facebook"),
        ]
        let rules = generator.generateRules(from: items)
        #expect(rules.count == 3)
    }

    @Test func rulesHaveSequentialIds() {
        let items = [
            BlocklistItem(domain: "reddit.com", displayName: "Reddit"),
            BlocklistItem(domain: "twitter.com", displayName: "Twitter"),
        ]
        let rules = generator.generateRules(from: items)
        #expect(rules[0].id == 1)
        #expect(rules[1].id == 2)
    }

    @Test func rulesHaveCorrectUrlFilter() {
        let items = [
            BlocklistItem(domain: "reddit.com", displayName: "Reddit"),
        ]
        let rules = generator.generateRules(from: items)
        #expect(rules.count == 1)
        #expect(rules[0].condition.urlFilter == "||reddit.com")
    }

    @Test func rulesTargetMainFrame() {
        let items = [
            BlocklistItem(domain: "example.com", displayName: "Example"),
        ]
        let rules = generator.generateRules(from: items)
        #expect(rules[0].condition.resourceTypes == ["main_frame"])
    }

    @Test func rulesPriorityIsOne() {
        let items = [
            BlocklistItem(domain: "example.com", displayName: "Example"),
        ]
        let rules = generator.generateRules(from: items)
        #expect(rules[0].priority == 1)
    }

    // MARK: - Block Mode: Soft Warn (Redirect)

    @Test func softWarnModeGeneratesRedirect() {
        let items = [
            BlocklistItem(domain: "reddit.com", displayName: "Reddit", blockMode: .softWarn),
        ]
        let rules = generator.generateRules(from: items)
        #expect(rules.count == 1)
        #expect(rules[0].action.type == "redirect")
        #expect(rules[0].action.redirect != nil)
        #expect(rules[0].action.redirect?.extensionPath == "/blocked.html?domain=reddit.com")
    }

    // MARK: - Block Mode: Hard Block

    @Test func hardBlockModeGeneratesBlock() {
        let items = [
            BlocklistItem(domain: "twitter.com", displayName: "Twitter", blockMode: .hardBlock),
        ]
        let rules = generator.generateRules(from: items)
        #expect(rules.count == 1)
        #expect(rules[0].action.type == "block")
        #expect(rules[0].action.redirect == nil)
    }

    // MARK: - Block Mode: Timed Lock

    @Test func timedLockModeGeneratesBlock() {
        let items = [
            BlocklistItem(domain: "facebook.com", displayName: "Facebook", blockMode: .timedLock),
        ]
        let rules = generator.generateRules(from: items)
        #expect(rules.count == 1)
        #expect(rules[0].action.type == "block")
        #expect(rules[0].action.redirect == nil)
    }

    // MARK: - Mixed Block Modes

    @Test func mixedBlockModes() {
        let items = [
            BlocklistItem(domain: "reddit.com", displayName: "Reddit", blockMode: .softWarn),
            BlocklistItem(domain: "twitter.com", displayName: "Twitter", blockMode: .hardBlock),
            BlocklistItem(domain: "facebook.com", displayName: "Facebook", blockMode: .timedLock),
        ]
        let rules = generator.generateRules(from: items)
        #expect(rules.count == 3)
        #expect(rules[0].action.type == "redirect")
        #expect(rules[1].action.type == "block")
        #expect(rules[2].action.type == "block")
    }

    // MARK: - Filtering Behavior

    @Test func emptyBlocklistReturnsEmptyRules() {
        let rules = generator.generateRules(from: [])
        #expect(rules.isEmpty)
    }

    @Test func filtersOutDisabledItems() {
        let items = [
            BlocklistItem(domain: "reddit.com", displayName: "Reddit", isEnabled: true),
            BlocklistItem(domain: "twitter.com", displayName: "Twitter", isEnabled: false),
        ]
        let rules = generator.generateRules(from: items)
        #expect(rules.count == 1)
        #expect(rules[0].condition.urlFilter == "||reddit.com")
    }

    @Test func filtersOutAppOnlyItems() {
        let items = [
            BlocklistItem(bundleId: "com.twitter.ios", displayName: "Twitter"),
            BlocklistItem(domain: "reddit.com", displayName: "Reddit"),
        ]
        let rules = generator.generateRules(from: items)
        #expect(rules.count == 1)
        #expect(rules[0].condition.urlFilter == "||reddit.com")
    }

    @Test func allDisabledReturnsEmpty() {
        let items = [
            BlocklistItem(domain: "reddit.com", displayName: "Reddit", isEnabled: false),
            BlocklistItem(domain: "twitter.com", displayName: "Twitter", isEnabled: false),
        ]
        let rules = generator.generateRules(from: items)
        #expect(rules.isEmpty)
    }

    // MARK: - Wildcard and Subdomain Domains

    @Test func wildcardDomain() {
        let items = [
            BlocklistItem(domain: "*.reddit.com", displayName: "Reddit All"),
        ]
        let rules = generator.generateRules(from: items)
        #expect(rules.count == 1)
        #expect(rules[0].condition.urlFilter == "||*.reddit.com")
    }

    @Test func subdomainInDomain() {
        let items = [
            BlocklistItem(domain: "www.reddit.com", displayName: "Reddit WWW"),
        ]
        let rules = generator.generateRules(from: items)
        #expect(rules.count == 1)
        #expect(rules[0].condition.urlFilter == "||www.reddit.com")
    }

    // MARK: - JSON Generation

    @Test func generateJSONFromDomainList() throws {
        let items = [
            BlocklistItem(domain: "reddit.com", displayName: "Reddit"),
            BlocklistItem(domain: "twitter.com", displayName: "Twitter"),
        ]
        let jsonData = try generator.generateJSON(from: items)
        #expect(!jsonData.isEmpty)

        // Verify it's valid JSON
        let decoded = try JSONDecoder().decode([ContentBlockerRuleGenerator.DNRRule].self, from: jsonData)
        #expect(decoded.count == 2)
    }

    @Test func generateJSONFromEmptyList() throws {
        let jsonData = try generator.generateJSON(from: [])
        #expect(!jsonData.isEmpty)

        let decoded = try JSONDecoder().decode([ContentBlockerRuleGenerator.DNRRule].self, from: jsonData)
        #expect(decoded.isEmpty)
    }

    @Test func generatedJSONIsPrettyPrinted() throws {
        let items = [
            BlocklistItem(domain: "example.com", displayName: "Example"),
        ]
        let jsonData = try generator.generateJSON(from: items)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        // Pretty-printed JSON contains newlines
        #expect(jsonString.contains("\n"))
    }

    // MARK: - DNRRule Codable Conformance

    @Test func dnrRuleRoundtrip() throws {
        let rule = ContentBlockerRuleGenerator.DNRRule(
            id: 1,
            priority: 1,
            action: .init(type: "block"),
            condition: .init(urlFilter: "||example.com", resourceTypes: ["main_frame"])
        )

        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(ContentBlockerRuleGenerator.DNRRule.self, from: data)

        #expect(decoded.id == 1)
        #expect(decoded.action.type == "block")
        #expect(decoded.action.redirect == nil)
        #expect(decoded.condition.urlFilter == "||example.com")
        #expect(decoded.condition.resourceTypes == ["main_frame"])
    }

    @Test func dnrRuleWithRedirectRoundtrip() throws {
        let rule = ContentBlockerRuleGenerator.DNRRule(
            id: 1,
            priority: 1,
            action: .init(type: "redirect", redirect: .init(extensionPath: "/blocked.html")),
            condition: .init(urlFilter: "||example.com", resourceTypes: ["main_frame"])
        )

        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(ContentBlockerRuleGenerator.DNRRule.self, from: data)

        #expect(decoded.action.type == "redirect")
        #expect(decoded.action.redirect?.extensionPath == "/blocked.html")
    }
}
