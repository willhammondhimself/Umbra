import SwiftUI
import TetherKit

struct IOSIntegrationsView: View {
    @State private var integrations: [IntegrationResponse] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var isImporting = false
    @State private var importResult: String?
    @State private var showTokenSheet = false
    @State private var pendingProvider = ""
    @State private var tokenInput = ""

    var body: some View {
        List {
            Section("Slack") {
                slackRow
            }

            Section("Task Import") {
                todoistRow
                notionRow

                if isImporting {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Importing...")
                            .foregroundStyle(.secondary)
                    }
                }

                if let importResult {
                    Text(importResult)
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }
            }

            if let error {
                Section {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Integrations")
        .task {
            await loadIntegrations()
        }
        .sheet(isPresented: $showTokenSheet) {
            tokenInputSheet
        }
    }

    // MARK: - Row Views

    private var slackRow: some View {
        HStack {
            Label("Slack", systemImage: "bubble.left.fill")
            Spacer()
            if let integration = integration(for: "slack") {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                    Text("Connected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Slack connected. Tap to disconnect")
                .onTapGesture {
                    Task { await disconnectIntegration(integration.id) }
                }
            } else {
                Button("Connect") {
                    pendingProvider = "slack"
                    showTokenSheet = true
                }
                .font(.caption)
            }
        }
    }

    private var todoistRow: some View {
        HStack {
            Label("Todoist", systemImage: "checkmark.circle")
            Spacer()
            if isIntegrationConnected("todoist") {
                Button("Import") {
                    Task { await importTodoistTasks() }
                }
                .font(.caption)
                .disabled(isImporting)
                .accessibilityLabel("Import tasks from Todoist")
                .accessibilityHint(isImporting ? "Import in progress" : "Imports your Todoist tasks into Tether")
            } else {
                Button("Connect") {
                    pendingProvider = "todoist"
                    showTokenSheet = true
                }
                .font(.caption)
                .accessibilityLabel("Connect Todoist")
                .accessibilityHint("Enter your Todoist API token to enable task import")
            }
        }
    }

    private var notionRow: some View {
        HStack {
            Label("Notion", systemImage: "doc.text")
            Spacer()
            if isIntegrationConnected("notion") {
                Button("Import") {
                    Task { await importNotionTasks() }
                }
                .font(.caption)
                .disabled(isImporting)
                .accessibilityLabel("Import tasks from Notion")
                .accessibilityHint(isImporting ? "Import in progress" : "Imports your Notion tasks into Tether")
            } else {
                Button("Connect") {
                    pendingProvider = "notion"
                    showTokenSheet = true
                }
                .font(.caption)
                .accessibilityLabel("Connect Notion")
                .accessibilityHint("Enter your Notion API token to enable task import")
            }
        }
    }

    private var tokenInputSheet: some View {
        NavigationStack {
            Form {
                Section("Connect \(pendingProvider.capitalized)") {
                    SecureField("API Token", text: $tokenInput)

                    Text("Enter your \(pendingProvider.capitalized) API token to connect.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Connect \(pendingProvider.capitalized)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showTokenSheet = false
                        tokenInput = ""
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await connectIntegration(pendingProvider, token: tokenInput)
                            showTokenSheet = false
                            tokenInput = ""
                        }
                    }
                    .disabled(tokenInput.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Data Loading

    private func loadIntegrations() async {
        isLoading = true
        defer { isLoading = false }
        error = nil
        do {
            integrations = try await APIClient.shared.request(.integrations)
        } catch {
            self.error = "Failed to load integrations: \(error.localizedDescription)"
        }
    }

    // MARK: - Integration Actions

    private func integration(for provider: String) -> IntegrationResponse? {
        integrations.first { $0.provider == provider && $0.isActive }
    }

    private func isIntegrationConnected(_ provider: String) -> Bool {
        integration(for: provider) != nil
    }

    private func connectIntegration(_ provider: String, token: String) async {
        error = nil
        do {
            let body = IntegrationCreateRequest(provider: provider, accessToken: token)
            let integration: IntegrationResponse = try await APIClient.shared.request(
                .integrations, method: "POST", body: body
            )
            if let idx = integrations.firstIndex(where: { $0.id == integration.id }) {
                integrations[idx] = integration
            } else {
                integrations.append(integration)
            }
        } catch {
            self.error = "Failed to connect \(provider): \(error.localizedDescription)"
        }
    }

    private func disconnectIntegration(_ id: UUID) async {
        error = nil
        do {
            try await APIClient.shared.requestVoid(.integrationById(id), method: "DELETE")
            integrations.removeAll { $0.id == id }
        } catch {
            self.error = "Failed to disconnect: \(error.localizedDescription)"
        }
    }

    // MARK: - Task Import

    private func importTodoistTasks() async {
        isImporting = true
        importResult = nil
        defer { isImporting = false }
        do {
            let body = TaskImportRequest(projectId: nil)
            let result: TaskImportAPIResponse = try await APIClient.shared.request(
                .todoistImport, method: "POST", body: body
            )
            importResult = "Imported \(result.importedCount) tasks from Todoist"
        } catch {
            self.error = "Todoist import failed: \(error.localizedDescription)"
        }
    }

    private func importNotionTasks() async {
        isImporting = true
        importResult = nil
        defer { isImporting = false }
        do {
            let body = TaskImportRequest(projectId: nil)
            let result: TaskImportAPIResponse = try await APIClient.shared.request(
                .notionImport, method: "POST", body: body
            )
            importResult = "Imported \(result.importedCount) tasks from Notion"
        } catch {
            self.error = "Notion import failed: \(error.localizedDescription)"
        }
    }
}
