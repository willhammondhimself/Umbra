import SwiftUI
import UmbraKit

@main
struct UmbraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var authManager = AuthManager.shared

    var body: some Scene {
        WindowGroup {
            OnboardingView()
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 900, height: 640)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let menuBarManager = MenuBarManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarManager.setup()
    }
}
