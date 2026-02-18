import SafariServices
import os

/// Native message handler for the Tether Safari Web Extension.
/// Reads blocklist rules from the shared app group container and sends them
/// to the extension's background.js via native messaging.
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    private let logger = Logger(subsystem: "com.willhammond.tether.safari", category: "extension")
    private let suiteName = "group.com.willhammond.tether.shared"
    private let rulesKey = "safari_blocklist_rules"
    private let sessionActiveKey = "is_session_active"

    func beginRequest(with context: NSExtensionContext) {
        let item = context.inputItems.first as? NSExtensionItem
        let message = item?.userInfo?[SFExtensionMessageKey] as? [String: Any]

        let action = message?["action"] as? String ?? "getRules"
        logger.info("Received message: \(action)")

        let defaults = UserDefaults(suiteName: suiteName)
        var response: [String: Any] = [:]

        switch action {
        case "getRules":
            let isActive = defaults?.bool(forKey: sessionActiveKey) ?? false
            if isActive, let rulesData = defaults?.data(forKey: rulesKey),
               let rulesJSON = try? JSONSerialization.jsonObject(with: rulesData) {
                response["rules"] = rulesJSON
                response["isActive"] = true
            } else {
                response["rules"] = []
                response["isActive"] = isActive
            }

        case "getStatus":
            response["isActive"] = defaults?.bool(forKey: sessionActiveKey) ?? false

        default:
            response["error"] = "Unknown action: \(action)"
        }

        let responseItem = NSExtensionItem()
        responseItem.userInfo = [SFExtensionMessageKey: response]
        context.completeRequest(returningItems: [responseItem])
    }
}
