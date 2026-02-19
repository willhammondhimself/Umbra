import SwiftUI
import TetherKit

struct IOSTaskListView: View {
    @State private var tasks: [TetherTask] = []
    @State private var isRefreshing = false

    // Chat / NL parsing
    @State private var chatInput = ""
    @State private var parsedTasks: [ParsedTask] = []
    @State private var showManualForm = false

    private let parsingService = NLParsingService()

    var body: some View {
        VStack(spacing: 0) {
            // Chat input
            IOSChatInputView(inputText: $chatInput) { text in
                let results = parsingService.parse(text)
                withAnimation {
                    parsedTasks.append(contentsOf: results)
                }
            }

            // Parsed task cards
            if !parsedTasks.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(parsedTasks.indices, id: \.self) { index in
                            IOSParsedTaskCard(
                                parsedTask: $parsedTasks[index],
                                onAccept: { acceptParsedTask(at: index) },
                                onDiscard: { discardParsedTask(at: index) }
                            )
                            .frame(width: 280)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 4)
                }

                HStack {
                    Button("Accept All") {
                        acceptAllParsedTasks()
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonStyle(.tetherPressable)
                    .controlSize(.small)

                    Button("Discard All") {
                        withAnimation(.tetherQuick) { parsedTasks.removeAll() }
                    }
                    .buttonStyle(.bordered)
                    .buttonStyle(.tetherPressable)
                    .controlSize(.small)

                    Spacer()

                    Text("\(parsedTasks.count) extracted")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            Divider()

            // Task list
            List {
                if tasks.isEmpty {
                    ContentUnavailableView(
                        "No Tasks",
                        systemImage: "text.badge.plus",
                        description: Text("Type your plans above to create tasks.")
                    )
                } else {
                    ForEach(tasks) { task in
                        HStack(spacing: 10) {
                            Button {
                                withAnimation(.tetherQuick) {
                                    toggleStatus(task)
                                }
                            } label: {
                                Image(systemName: task.status == .done ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(task.status == .done ? Color.tetherFocused : .secondary)
                                    .contentTransition(.symbolEffect(.replace))
                            }
                            .buttonStyle(.tetherPressable)
                            .accessibilityLabel(task.status == .done ? "Mark as to do" : "Mark as done")
                            .accessibilityValue(task.status == .done ? "Completed" : "To do")

                            VStack(alignment: .leading, spacing: 2) {
                                Text(task.title)
                                    .strikethrough(task.status == .done)
                                if let estimate = task.estimateMinutes {
                                    Text("\(estimate) min")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            priorityBadge(task.priority)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                deleteTask(task)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .refreshable {
                await refresh()
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showManualForm = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add task manually")
            }
        }
        .sheet(isPresented: $showManualForm) {
            IOSManualTaskForm { task in
                saveTask(task)
            }
        }
        .onAppear(perform: loadTasks)
    }

    // MARK: - Components

    @ViewBuilder
    private func priorityBadge(_ priority: TetherTask.Priority) -> some View {
        if priority != .medium {
            Text(priorityLabel(priority))
                .font(.caption2)
                .fontWeight(.semibold)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    priority >= .high ? Color.tetherDistracted.opacity(0.15) : Color.tetherNeutral.opacity(0.15),
                    in: .capsule
                )
                .foregroundStyle(priority >= .high ? Color.tetherDistracted : Color.tetherNeutral)
        }
    }

    private func priorityLabel(_ priority: TetherTask.Priority) -> String {
        switch priority {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        case .urgent: "Urgent"
        }
    }

    // MARK: - Parsed Task Actions

    private func acceptParsedTask(at index: Int) {
        guard parsedTasks.indices.contains(index) else { return }
        let parsed = parsedTasks[index]

        var projectId: Int64?
        if let projectName = parsed.projectName {
            projectId = findOrCreateProject(name: projectName)
        }

        let task = TetherTask(
            projectId: projectId,
            title: parsed.title,
            estimateMinutes: parsed.estimateMinutes,
            priority: parsed.priority
        )
        saveTask(task)

        withAnimation {
            parsedTasks.remove(at: index)
        }
    }

    private func acceptAllParsedTasks() {
        for parsed in parsedTasks {
            var projectId: Int64?
            if let projectName = parsed.projectName {
                projectId = findOrCreateProject(name: projectName)
            }
            let task = TetherTask(
                projectId: projectId,
                title: parsed.title,
                estimateMinutes: parsed.estimateMinutes,
                priority: parsed.priority
            )
            saveTask(task)
        }
        withAnimation { parsedTasks.removeAll() }
    }

    private func discardParsedTask(at index: Int) {
        withAnimation {
            if parsedTasks.indices.contains(index) {
                parsedTasks.remove(at: index)
            }
        }
    }

    private func findOrCreateProject(name: String) -> Int64? {
        do {
            let existing = try DatabaseManager.shared.fetchProjects()
            if let found = existing.first(where: { $0.name.lowercased() == name.lowercased() }) {
                return found.id
            }
            var project = Project(name: name)
            try DatabaseManager.shared.saveProject(&project)
            return project.id
        } catch {
            return nil
        }
    }

    // MARK: - Task Actions

    private func loadTasks() {
        do {
            tasks = try DatabaseManager.shared.fetchTasks()
        } catch {
            // Non-critical
        }
    }

    private func saveTask(_ task: TetherTask) {
        do {
            var mutableTask = task
            if mutableTask.id == nil {
                mutableTask.sortOrder = try DatabaseManager.shared.nextSortOrder(projectId: mutableTask.projectId)
            }
            try DatabaseManager.shared.saveTask(&mutableTask)
            loadTasks()
        } catch {
            // Non-critical
        }
    }

    private func toggleStatus(_ task: TetherTask) {
        var updated = task
        switch task.status {
        case .todo: updated.status = .done
        case .inProgress: updated.status = .done
        case .done: updated.status = .todo
        }
        saveTask(updated)
    }

    private func deleteTask(_ task: TetherTask) {
        do {
            try DatabaseManager.shared.deleteTask(task)
            loadTasks()
        } catch {
            // Non-critical
        }
    }

    private func refresh() async {
        SyncManager.shared.triggerSync()
        try? await Task.sleep(for: .seconds(1))
        loadTasks()
    }
}

// MARK: - Manual Task Form

struct IOSManualTaskForm: View {
    var onSave: (TetherTask) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var priority: TetherTask.Priority = .medium
    @State private var estimateMinutes: Int?
    @State private var estimateText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("What do you need to do?", text: $title)
                }

                Section("Priority") {
                    Picker("Priority", selection: $priority) {
                        ForEach(TetherTask.Priority.allCases, id: \.self) { p in
                            Label(p.label, systemImage: p.iconName).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Estimate") {
                    TextField("Minutes (optional)", text: $estimateText)
                        .keyboardType(.numberPad)
                        .onChange(of: estimateText) { _, newValue in
                            estimateMinutes = Int(newValue)
                        }
                }
            }
            .navigationTitle("New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let task = TetherTask(
                            title: title,
                            estimateMinutes: estimateMinutes,
                            priority: priority
                        )
                        onSave(task)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
