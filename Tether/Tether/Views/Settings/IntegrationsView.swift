import SwiftUI
import TetherKit

struct IntegrationsView: View {
    @State private var webhooks: [WebhookResponse] = []
    @State private var integrations: [IntegrationResponse] = []
    @State private var isLoading = false
    @State private var error: String?

    // Webhook creation
    @State private var showAddWebhook = false
    @State private var newWebhookURL = ""
    @State private var selectedEvents: Set<String> = []

    // Import state
    @State private var isImporting = false
    @State private var importResult: String?

    private let availableEvents = ["session.start", "session.end", "task.complete"]

    var body: some View {
        Form {
            Section("Webhooks") {
                if webhooks.isEmpty && !isLoading {
                    Text("No webhooks configured")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(webhooks, id: \.id) { webhook in
                        WebhookRow(webhook: webhook, onDelete: {
                            Task { await deleteWebhook(webhook.id) }
                        }, onTest: {
                            Task { await testWebhook(webhook.id) }
                        })
                    }
                }

                Button("Add Webhook") {
                    showAddWebhook = true
                }
            }

            Section("Slack") {
                IntegrationToggleRow(
                    provider: "slack",
                    icon: "bubble.left.fill",
                    description: "Set focus status and enable DND during sessions",
                    integrations: integrations,
                    onConnect: { token in
                        Task { await connectIntegration("slack", token: token) }
                    },
                    onDisconnect: { id in
                        Task { await disconnectIntegration(id) }
                    }
                )
            }

            Section("Task Import") {
                HStack {
                    Label("Todoist", systemImage: "checkmark.circle")
                    Spacer()
                    if isIntegrationConnected("todoist") {
                        Button("Import Tasks") {
                            Task { await importTodoistTasks() }
                        }
                        .disabled(isImporting)
                    } else {
                        Button("Connect") {
                            Task { await promptForToken("todoist") }
                        }
                    }
                }

                HStack {
                    Label("Notion", systemImage: "doc.text")
                    Spacer()
                    if isIntegrationConnected("notion") {
                        Button("Import Tasks") {
                            Task { await importNotionTasks() }
                        }
                        .disabled(isImporting)
                    } else {
                        Button("Connect") {
                            Task { await promptForToken("notion") }
                        }
                    }
                }

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
        .formStyle(.grouped)
        .task {
            await loadAll()
        }
        .sheet(isPresented: $showAddWebhook) {
            AddWebhookSheet(
                url: $newWebhookURL,
                selectedEvents: $selectedEvents,
                availableEvents: availableEvents,
                onSave: {
                    Task {
                        await createWebhook()
                        showAddWebhook = false
                    }
                },
                onCancel: { showAddWebhook = false }
            )
        }
    }

    // MARK: - Data Loading

    private func loadAll() async {
        isLoading = true
        defer { isLoading = false }
        error = nil

        do {
            webhooks = try await APIClient.shared.request(.webhooks)
            integrations = try await APIClient.shared.request(.integrations)
        } catch {
            self.error = "Failed to load: \(error.localizedDescription)"
        }
    }

    // MARK: - Webhook Actions

    private func createWebhook() async {
        guard !newWebhookURL.isEmpty, !selectedEvents.isEmpty else { return }
        error = nil
        do {
            let body = WebhookCreateRequest(
                url: newWebhookURL,
                events: Array(selectedEvents)
            )
            let webhook: WebhookResponse = try await APIClient.shared.request(
                .webhooks, method: "POST", body: body
            )
            webhooks.insert(webhook, at: 0)
            newWebhookURL = ""
            selectedEvents = []
        } catch {
            self.error = "Failed to create webhook: \(error.localizedDescription)"
        }
    }

    private func deleteWebhook(_ id: UUID) async {
        error = nil
        do {
            try await APIClient.shared.requestVoid(.webhookById(id), method: "DELETE")
            webhooks.removeAll { $0.id == id }
        } catch {
            self.error = "Failed to delete webhook: \(error.localizedDescription)"
        }
    }

    private func testWebhook(_ id: UUID) async {
        error = nil
        do {
            let _: WebhookTestResponse = try await APIClient.shared.request(
                .webhookTest(id), method: "POST"
            )
        } catch {
            self.error = "Test delivery failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Integration Actions

    private func isIntegrationConnected(_ provider: String) -> Bool {
        integrations.contains { $0.provider == provider && $0.isActive }
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

    private func promptForToken(_ provider: String) async {
        // In a full implementation this would open an OAuth flow.
        // For now, prompt for an API token via a text field.
        // This is a placeholder that connects with an empty token.
        await connectIntegration(provider, token: "")
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

// MARK: - Subviews

private struct WebhookRow: View {
    let webhook: WebhookResponse
    let onDelete: () -> Void
    let onTest: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(webhook.url)
                .font(.body)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: 4) {
                ForEach(webhook.events, id: \.self) { event in
                    Text(event)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: .capsule)
                }
            }

            HStack {
                Button("Test", action: onTest)
                    .controlSize(.small)
                Button("Delete", role: .destructive, action: onDelete)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct IntegrationToggleRow: View {
    let provider: String
    let icon: String
    let description: String
    let integrations: [IntegrationResponse]
    let onConnect: (String) -> Void
    let onDisconnect: (UUID) -> Void

    @State private var tokenInput = ""
    @State private var showTokenField = false

    private var integration: IntegrationResponse? {
        integrations.first { $0.provider == provider && $0.isActive }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(provider.capitalized, systemImage: icon)
                    .font(.body)
                Spacer()
                if let integration {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                            .accessibilityHidden(true)
                        Text("Connected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Disconnect") {
                            onDisconnect(integration.id)
                        }
                        .controlSize(.small)
                    }
                } else {
                    Button("Connect") {
                        showTokenField = true
                    }
                    .controlSize(.small)
                }
            }

            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)

            if showTokenField {
                HStack {
                    SecureField("API Token", text: $tokenInput)
                        .textFieldStyle(.roundedBorder)
                    Button("Save") {
                        onConnect(tokenInput)
                        tokenInput = ""
                        showTokenField = false
                    }
                    .disabled(tokenInput.isEmpty)
                    Button("Cancel") {
                        showTokenField = false
                        tokenInput = ""
                    }
                }
            }
        }
    }
}

private struct AddWebhookSheet: View {
    @Binding var url: String
    @Binding var selectedEvents: Set<String>
    let availableEvents: [String]
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Webhook")
                .font(.headline)

            TextField("Webhook URL", text: $url)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 8) {
                Text("Events")
                    .font(.subheadline)
                    .fontWeight(.medium)

                ForEach(availableEvents, id: \.self) { event in
                    Toggle(event, isOn: Binding(
                        get: { selectedEvents.contains(event) },
                        set: { isOn in
                            if isOn {
                                selectedEvents.insert(event)
                            } else {
                                selectedEvents.remove(event)
                            }
                        }
                    ))
                }
            }

            HStack {
                Button("Cancel", action: onCancel)
                Spacer()
                Button("Create", action: onSave)
                    .disabled(url.isEmpty || selectedEvents.isEmpty)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 400)
    }
}

