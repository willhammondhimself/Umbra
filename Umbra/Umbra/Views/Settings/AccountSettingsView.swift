import SwiftUI

struct AccountSettingsView: View {
    @State private var authManager = AuthManager.shared
    @State private var visibility = "private"
    @State private var showDeleteConfirmation = false

    var body: some View {
        Form {
            Section("Profile") {
                if let user = authManager.currentUser {
                    LabeledContent("Email", value: user.email)
                    LabeledContent("Name", value: user.displayName ?? "Not set")
                }
            }

            Section("Privacy") {
                Picker("Profile Visibility", selection: $visibility) {
                    Text("Private").tag("private")
                    Text("Friends Only").tag("friends")
                    Text("Groups").tag("groups")
                }
                .pickerStyle(.segmented)

                Text("Controls who can see your stats on leaderboards.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Data") {
                Button("Export Data (JSON)") {
                    // TODO: Trigger data export via /account/export
                }

                Button("Delete Account", role: .destructive) {
                    showDeleteConfirmation = true
                }
            }

            Section {
                Button("Log Out") {
                    authManager.logout()
                }
                .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .alert("Delete Account?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                // TODO: Call DELETE /account endpoint
                authManager.logout()
            }
        } message: {
            Text("This will permanently delete all your data. This cannot be undone.")
        }
    }
}
