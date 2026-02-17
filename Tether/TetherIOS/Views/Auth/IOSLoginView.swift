import AuthenticationServices
import SwiftUI
import TetherKit

struct IOSLoginView: View {
    @State private var authManager = AuthManager.shared

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // App icon and title
            VStack(spacing: 12) {
                Image(systemName: "shield.checkered")
                    .font(.system(size: 72))
                    .foregroundStyle(Color.accentColor)

                Text("Tether")
                    .font(.largeTitle.bold())

                Text("Your productivity accountability coach")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 40)

            Spacer()

            // Sign in buttons
            VStack(spacing: 16) {
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.email, .fullName]
                } onCompletion: { _ in
                    // Handled by AuthManager delegate
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)
                .frame(maxWidth: 320)

                Button {
                    authManager.signInWithGoogle()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "globe")
                        Text("Sign in with Google")
                    }
                    .frame(maxWidth: 320)
                    .frame(height: 50)
                }
                .buttonStyle(.bordered)
            }

            if authManager.isLoading {
                ProgressView()
            }

            Spacer()
                .frame(height: 32)

            // Demo mode
            Button("Demo Mode (No Auth)") {
                authManager.setDemoMode()
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.bottom, 16)
        }
        .onAppear {
            authManager.signInWithApple()
        }
    }
}
