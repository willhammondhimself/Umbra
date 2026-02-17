import AuthenticationServices
import SwiftUI
import UmbraKit

struct LoginView: View {
    @State private var authManager = AuthManager.shared

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // App icon and title
            VStack(spacing: 12) {
                Image(systemName: "shield.checkered")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.accentColor)

                Text("Umbra")
                    .font(.largeTitle.bold())

                Text("Your productivity accountability coach")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Sign in buttons
            VStack(spacing: 16) {
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.email, .fullName]
                } onCompletion: { _ in
                    // Handled by AuthManager delegate
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 44)
                .frame(maxWidth: 280)

                Button {
                    authManager.signInWithGoogle()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "globe")
                        Text("Sign in with Google")
                    }
                    .frame(maxWidth: 280)
                    .frame(height: 44)
                }
                .buttonStyle(.bordered)
            }

            if authManager.isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            Spacer()
                .frame(height: 40)

            // Demo mode for local testing
            Button("Demo Mode (No Auth)") {
                authManager.setDemoMode()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            authManager.signInWithApple()
        }
    }
}
