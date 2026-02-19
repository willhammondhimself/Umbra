import SwiftUI
import TetherKit

struct IOSLoginView: View {
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
                    .font(TetherFont.iconHero)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)

                Text("Tether")
                    .font(.largeTitle.bold())

                Text("Your productivity accountability coach")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 40)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Tether. Your productivity accountability coach.")

            Spacer()

            Group {
                if showEmailForm {
                    emailFormView
                } else {
                    oauthButtonsView
                }
            }
            .padding(TetherSpacing.xxl)
            .glassCard(cornerRadius: TetherRadius.card)

            if authManager.isLoading {
                ProgressView()
                    .accessibilityLabel("Signing in")
            }

            if let error = authManager.authError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Color.tetherError)
                    .padding(.horizontal)
                    .accessibilityLabel("Error: \(error)")
            }

            Spacer()
                .frame(height: 32)

            #if DEBUG
            Button("Demo Mode (No Auth)") {
                authManager.setDemoMode()
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.bottom, TetherSpacing.lg)
            #endif
        }
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
                .frame(maxWidth: 320)
                .frame(height: 50)
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
                .frame(maxWidth: 320)
                .frame(height: 50)
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
                .frame(maxWidth: 320)
                .frame(height: 50)
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
                    .textContentType(.name)
                    .padding(.horizontal, 40)
            }

            TextField("Email", text: $email)
                .textFieldStyle(.roundedBorder)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(.horizontal, 40)

            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
                .textContentType(isRegistering ? .newPassword : .password)
                .padding(.horizontal, 40)
                .onSubmit { submitEmailForm() }

            Button(isRegistering ? "Create Account" : "Sign In") {
                submitEmailForm()
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: 320)
            .frame(height: 50)
            .disabled(email.isEmpty || password.count < 8)
            .accessibilityHint(email.isEmpty || password.count < 8 ? "Enter email and password with at least 8 characters" : "")

            HStack {
                Button(isRegistering ? "Sign In Instead" : "Create Account") {
                    withMotionAwareAnimation(.tetherQuick, reduceMotion: reduceMotion) { isRegistering.toggle() }
                }
                .font(.footnote)

                if !isRegistering {
                    Text("·").foregroundStyle(.secondary)
                    Button("Forgot Password?") {
                        resetEmail = email
                        showForgotPassword = true
                    }
                    .font(.footnote)
                }
            }

            Button("Back") {
                withMotionAwareAnimation(.tetherQuick, reduceMotion: reduceMotion) { showEmailForm = false }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    private var forgotPasswordSheet: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if resetSent {
                    Label("Check your email for a reset link.", systemImage: "checkmark.circle")
                        .foregroundStyle(Color.tetherSuccess)
                        .padding()
                } else {
                    TextField("Email", text: $resetEmail)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .padding(.horizontal)

                    Button("Send Reset Link") {
                        Task {
                            resetSent = await authManager.requestPasswordReset(email: resetEmail)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(resetEmail.isEmpty)
                }
            }
            .navigationTitle("Reset Password")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showForgotPassword = false }
                }
            }
        }
        .presentationDetents([.medium])
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
