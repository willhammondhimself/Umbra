import SwiftUI

struct OnboardingView: View {
    @State private var authManager = AuthManager.shared

    var body: some View {
        Group {
            if authManager.isAuthenticated {
                ContentView()
            } else {
                LoginView()
            }
        }
    }
}
