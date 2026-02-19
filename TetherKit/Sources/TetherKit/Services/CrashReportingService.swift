import Foundation
import Sentry

public final class CrashReportingService: Sendable {
    public static let shared = CrashReportingService()

    private init() {}

    public func initialize(dsn: String, environment: String = "production") {
        SentrySDK.start { options in
            options.dsn = dsn
            options.environment = environment
            options.tracesSampleRate = environment == "production" ? 0.2 : 1.0
            options.profilesSampleRate = 0.1
            options.enableAutoSessionTracking = true
            options.enableCaptureFailedRequests = true
            options.sendDefaultPii = false
            options.enableAppHangTracking = true
        }
    }

    public func setUser(id: String) {
        let user = Sentry.User()
        user.userId = id
        SentrySDK.setUser(user)
    }

    public func clearUser() {
        SentrySDK.setUser(nil)
    }

    public func addBreadcrumb(category: String, message: String, level: SentryLevel = .info) {
        let crumb = Breadcrumb(level: level, category: category)
        crumb.message = message
        SentrySDK.addBreadcrumb(crumb)
    }

    public func captureError(_ error: Error, context: [String: Any]? = nil) {
        if let context {
            SentrySDK.capture(error: error) { scope in
                scope.setContext(value: context, key: "custom")
            }
        } else {
            SentrySDK.capture(error: error)
        }
    }

    public func captureMessage(_ message: String, level: SentryLevel = .info) {
        SentrySDK.capture(message: message)
    }
}
