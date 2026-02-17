import AppKit
import SwiftUI
import UmbraKit
import UniformTypeIdentifiers

struct AccountSettingsView: View {
    @State private var authManager = AuthManager.shared
    @State private var visibility = "private"
    @State private var showDeleteConfirmation = false
    @State private var isExporting = false
    @State private var exportError: String?
    @State private var deleteError: String?
    @State private var visibilityError: String?

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
                .onChange(of: visibility) { oldValue, newValue in
                    Task { await saveVisibility(newValue) }
                }

                Text("Controls who can see your stats on leaderboards.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let visibilityError {
                    Text(visibilityError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Data") {
                Button {
                    Task { await exportData() }
                } label: {
                    HStack {
                        Text("Export Data (JSON)")
                        if isExporting {
                            Spacer()
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
                .disabled(isExporting)

                if let exportError {
                    Text(exportError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button("Delete Account", role: .destructive) {
                    showDeleteConfirmation = true
                }

                if let deleteError {
                    Text(deleteError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button("Log Out") {
                    authManager.logout()
                }
                .foregroundStyle(Color.umbraDistracted)
            }
        }
        .formStyle(.grouped)
        .alert("Delete Account?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task { await deleteAccount() }
            }
        } message: {
            Text("This will permanently delete all your data. This cannot be undone.")
        }
    }

    private func exportData() async {
        isExporting = true
        exportError = nil
        defer { isExporting = false }

        do {
            let jsonData = try await APIClient.shared.requestRawData(.accountExport)

            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "umbra-export.json"
            let result = await panel.begin()
            if result == .OK, let url = panel.url {
                try jsonData.write(to: url)
            }
        } catch {
            exportError = "Export failed: \(error.localizedDescription)"
        }
    }

    private func deleteAccount() async {
        deleteError = nil
        do {
            try await APIClient.shared.requestVoid(.accountDelete, method: "DELETE")
            authManager.logout()
        } catch {
            deleteError = "Delete failed: \(error.localizedDescription)"
        }
    }

    private func saveVisibility(_ newValue: String) async {
        visibilityError = nil
        do {
            struct VisibilityPayload: Encodable {
                let visibility: String
            }
            try await APIClient.shared.requestVoid(.accountSettings, method: "PATCH", body: VisibilityPayload(visibility: newValue))
        } catch {
            visibilityError = "Failed to save visibility: \(error.localizedDescription)"
            visibility = "private" // Reset on error
        }
    }
}
