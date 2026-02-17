import SwiftUI
import FamilyControls
import TetherKit

struct IOSSettingsView: View {
    @State private var authManager = AuthManager.shared
    @State private var blockingManager = ScreenTimeBlockingManager.shared
    @State private var showAppPicker = false

    var body: some View {
        List {
            Section("Account") {
                if authManager.isAuthenticated {
                    HStack {
                        Text("Signed In")
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.tetherFocused)
                    }

                    Button(role: .destructive) {
                        authManager.logout()
                    } label: {
                        Text("Sign Out")
                    }
                }
            }

            Section("Screen Time Blocking") {
                if blockingManager.isAuthorized {
                    HStack {
                        Text("Screen Time")
                        Spacer()
                        Text("Authorized")
                            .foregroundStyle(Color.tetherFocused)
                    }

                    Button("Select Apps to Block") {
                        showAppPicker = true
                    }
                } else {
                    Button("Enable Screen Time Blocking") {
                        Task { await blockingManager.requestAuthorization() }
                    }

                    Text("Screen Time blocking prevents you from opening distracting apps during focus sessions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Integrations") {
                NavigationLink {
                    IOSIntegrationsView()
                } label: {
                    Label("Third-Party Integrations", systemImage: "link")
                }
            }

            Section("Privacy") {
                NavigationLink("Privacy Policy") {
                    Text("Privacy policy content")
                        .padding()
                }
            }

            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.0.0")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .familyActivityPicker(
            isPresented: $showAppPicker,
            selection: $blockingManager.selectedApps
        )
    }
}
