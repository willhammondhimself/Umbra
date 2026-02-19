import SwiftUI
import TetherKit

struct LoginView: View {
    @State private var authManager = AuthManager.shared
    @State private var showEmailForm = false
    @State private var isRegistering = false
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var showForgotPassword = false
    @State private var resetEmail = ""
    @State private var resetSent = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "shield.checkered")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)

                Text("Tether")
                    .font(.largeTitle.bold())

                Text("Your productivity accountability coach")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Tether. Your productivity accountability coach.")

            Spacer()

            if showEmailForm {
                emailFormView
            } else {
                oauthButtonsView
            }

            if authManager.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Signing in")
            }

            if let error = authManager.authError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityLabel("Error: \(error)")
            }

            Spacer()
                .frame(height: 40)

            #if DEBUG
            Button("Demo Mode (No Auth)") {
                authManager.setDemoMode()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showForgotPassword) {
            forgotPasswordSheet
        }
    }

    private var oauthButtonsView: some View {
        VStack(spacing: 16) {
            Button {
                authManager.signInWithApple()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "apple.logo")
                    Text("Sign in with Apple")
                }
                .frame(maxWidth: 280)
                .frame(height: 44)
            }
            .buttonStyle(.borderedProminent)
            .buttonStyle(.tetherPressable)

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
            .buttonStyle(.tetherPressable)

            Button {
                withAnimation(reduceMotion ? .none : .tetherSpring) { showEmailForm = true }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "envelope")
                    Text("Sign in with Email")
                }
                .frame(maxWidth: 280)
                .frame(height: 44)
            }
            .buttonStyle(.bordered)
            .buttonStyle(.tetherPressable)
        }
    }

    private var emailFormView: some View {
        VStack(spacing: 16) {
            if isRegistering {
                TextField("Display Name (optional)", text: $displayName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
            }

            TextField("Email", text: $email)
                .textFieldStyle(.roundedBorder)
                .textContentType(.emailAddress)
                .frame(maxWidth: 280)

            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 280)
                .onSubmit { submitEmailForm() }

            Button(isRegistering ? "Create Account" : "Sign In") {
                submitEmailForm()
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: 280)
            .frame(height: 44)
            .disabled(email.isEmpty || password.count < 8)
            .accessibilityHint(email.isEmpty || password.count < 8 ? "Enter email and password with at least 8 characters" : "")

            HStack {
                Button(isRegistering ? "Already have an account? Sign In" : "Create Account") {
                    withAnimation(reduceMotion ? .none : .default) { isRegistering.toggle() }
                }
                .font(.caption)

                if !isRegistering {
                    Text("·").foregroundStyle(.secondary)
                    Button("Forgot Password?") {
                        resetEmail = email
                        showForgotPassword = true
                    }
                    .font(.caption)
                }
            }

            Button("Back to Sign In Options") {
                withAnimation(reduceMotion ? .none : .default) { showEmailForm = false }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var forgotPasswordSheet: some View {
        VStack(spacing: 20) {
            Text("Reset Password")
                .font(.title2.bold())

            if resetSent {
                Label("Check your email for a reset link.", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            } else {
                TextField("Email", text: $resetEmail)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 300)

                Button("Send Reset Link") {
                    Task {
                        resetSent = await authManager.requestPasswordReset(email: resetEmail)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(resetEmail.isEmpty)
            }

            Button("Close") { showForgotPassword = false }
                .foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(width: 400, height: 250)
    }

    private func submitEmailForm() {
        Task {
            if isRegistering {
                await authManager.registerWithEmail(
                    email: email,
                    password: password,
                    displayName: displayName.isEmpty ? nil : displayName
                )
            } else {
                await authManager.signInWithEmail(email: email, password: password)
            }
        }
    }
}
