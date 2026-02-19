import SwiftUI
import TetherKit
import UserNotifications

@main
struct TetherIOSApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var authManager = AuthManager.shared
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some Scene {
        WindowGroup {
            Group {
                if !authManager.isAuthenticated {
                    IOSLoginView()
                } else if !hasCompletedOnboarding {
                    IOSOnboardingView(onComplete: { hasCompletedOnboarding = true })
                } else {
                    IOSContentView()
                }
            }
            .onOpenURL { url in
                handleUniversalLink(url)
            }
        }
    }

    private func handleUniversalLink(_ url: URL) {
        // Handle tether.app/invite/{code} universal links
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let host = components.host,
              host.contains("tether.app") else { return }

        let path = components.path
        if path.hasPrefix("/invite/") {
            let code = String(path.dropFirst("/invite/".count))
            guard !code.isEmpty else { return }
            Task {
                try? await APIClient.shared.requestVoid(
                    .friendJoinLink(code),
                    method: "POST"
                )
            }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, @preconcurrency UNUserNotificationCenterDelegate, @unchecked Sendable {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Initialize observability
        CrashReportingService.shared.initialize(
            dsn: "YOUR_SENTRY_DSN_HERE",
            environment: ServerEnvironment.current == .production ? "production" : "development"
        )
        AnalyticsService.shared.initialize(appID: "YOUR_TELEMETRYDECK_APP_ID")
        AnalyticsService.shared.track(.appLaunched, parameters: ["platform": "ios"])

        // Set notification delegate before requesting authorization
        UNUserNotificationCenter.current().delegate = self

        // Register for push notifications
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            if granted {
                DispatchQueue.main.async {
                    application.registerForRemoteNotifications()
                }
            }
        }
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        Task {
            try? await APIClient.shared.requestVoid(
                .registerDevice,
                method: "POST",
                body: ["token": token, "platform": "ios"]
            )
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        return [.banner, .sound, .badge]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        TetherLogger.general.info("Notification tapped: \(userInfo)")
    }
}
