import SwiftUI
import TetherKit
import UserNotifications

@main
struct TetherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var authManager = AuthManager.shared

    var body: some Scene {
        WindowGroup {
            OnboardingView()
                .onOpenURL { url in
                    handleUniversalLink(url)
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 900, height: 640)
    }

    private func handleUniversalLink(_ url: URL) {
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

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, @preconcurrency UNUserNotificationCenterDelegate {
    let menuBarManager = MenuBarManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize observability
        CrashReportingService.shared.initialize(
            dsn: "YOUR_SENTRY_DSN_HERE",
            environment: ServerEnvironment.current == .production ? "production" : "development"
        )
        AnalyticsService.shared.initialize(appID: "YOUR_TELEMETRYDECK_APP_ID")
        AnalyticsService.shared.track(.appLaunched, parameters: ["platform": "macos"])

        menuBarManager.setup()

        // Check for crashed/incomplete sessions
        SessionManager.shared.checkForIncompleteSession()

        // Set notification delegate before requesting authorization
        UNUserNotificationCenter.current().delegate = self

        // Request push notification authorization and register
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            if granted {
                DispatchQueue.main.async {
                    NSApplication.shared.registerForRemoteNotifications()
                }
            }
        }
    }

    // MARK: - Remote Notification Registration

    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        Task {
            try? await APIClient.shared.requestVoid(
                .registerDevice,
                method: "POST",
                body: ["token": token, "platform": "macos"]
            )
        }
    }

    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        TetherLogger.general.error("Failed to register for remote notifications: \(error.localizedDescription)")
    }

    func applicationWillTerminate(_ notification: Notification) {
        SessionManager.shared.persistOnTermination()
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
