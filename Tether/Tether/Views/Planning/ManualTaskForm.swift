import SwiftUI
import TetherKit

struct ManualTaskForm: View {
    @Binding var isPresented: Bool
    var existingTask: TetherTask?
    var onSave: (TetherTask) -> Void

    @State private var title: String = ""
    @State private var estimateMinutes: Int?
    @State private var priority: TetherTask.Priority = .medium
    @State private var projectId: Int64?

    @State private var estimateText: String = ""
    @State private var projects: [Project] = []

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(existingTask == nil ? "New Task" : "Edit Task")
                    .font(.headline)
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            Form {
                // Title
                TextField("Task title", text: $title)
                    .textFieldStyle(.roundedBorder)

                // Priority
                Picker("Priority", selection: $priority) {
                    ForEach(TetherTask.Priority.allCases, id: \.self) { p in
                        Label(p.label, systemImage: p.iconName).tag(p)
                    }
                }

                // Estimate
                TextField("Estimate (e.g. 30, 90, 120)", text: $estimateText)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: estimateText) { _, newValue in
                        estimateMinutes = Int(newValue)
                    }

                if let minutes = estimateMinutes {
                    Text(formatMinutes(minutes))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Project
                if !projects.isEmpty {
                    Picker("Project", selection: $projectId) {
                        Text("No project").tag(nil as Int64?)
                        ForEach(projects) { project in
                            Text(project.name).tag(project.id as Int64?)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .frame(minHeight: 200)

            Divider()

            // Actions
            HStack {
                Spacer()
                Button("Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(width: 400, height: 380)
        .onAppear {
            if let task = existingTask {
                title = task.title
                estimateMinutes = task.estimateMinutes
                estimateText = task.estimateMinutes.map(String.init) ?? ""
                priority = task.priority
                projectId = task.projectId
            }
            loadProjects()
        }
    }

    private func save() {
        var task = existingTask ?? TetherTask(title: "")
        task.title = title.trimmingCharacters(in: .whitespaces)
        task.estimateMinutes = estimateMinutes
        task.priority = priority
        task.projectId = projectId
        onSave(task)
        isPresented = false
    }

    private func loadProjects() {
        do {
            projects = try DatabaseManager.shared.fetchProjects()
        } catch {
            projects = []
        }
    }

    private func formatMinutes(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) minutes" }
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "\(h) hour\(h == 1 ? "" : "s")" : "\(h)h \(m)m"
    }
}
