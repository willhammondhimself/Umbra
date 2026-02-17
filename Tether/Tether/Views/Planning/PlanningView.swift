import SwiftUI
import os
import TetherKit

struct PlanningView: View {
    @State private var tasks: [TetherTask] = []
    @State private var showingTaskForm = false
    @State private var editingTask: TetherTask?
    @State private var filterStatus: TetherTask.Status?

    // Chat / NL parsing
    @State private var chatInput = ""
    @State private var parsedTasks: [ParsedTask] = []

    private let parsingService = NLParsingService()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Plan")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text(taskSummary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                // Filter
                Picker("", selection: $filterStatus) {
                    Text("All").tag(nil as TetherTask.Status?)
                    ForEach(TetherTask.Status.allCases, id: \.self) { status in
                        Text(status.label).tag(status as TetherTask.Status?)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(minWidth: 160, maxWidth: 250)

                Button {
                    editingTask = nil
                    showingTaskForm = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .help("Add task manually")
                .keyboardShortcut("n", modifiers: .command)
            }
            .padding()

            // Chat input
            ChatInputView(inputText: $chatInput) { text in
                let results = parsingService.parse(text)
                withAnimation(.tetherQuick) {
                    parsedTasks.append(contentsOf: results)
                }
            }

            // Parsed task cards
            if !parsedTasks.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(parsedTasks.indices, id: \.self) { index in
                            ParsedTaskCard(
                                parsedTask: $parsedTasks[index],
                                onAccept: { acceptParsedTask(at: index) },
                                onDiscard: { discardParsedTask(at: index) }
                            )
                            .frame(width: 320)
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .scale.combined(with: .opacity)
                            ))
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }

                // Bulk actions
                HStack {
                    Button("Accept All") {
                        acceptAllParsedTasks()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button("Discard All") {
                        withAnimation { parsedTasks.removeAll() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Spacer()

                    Text("\(parsedTasks.count) task\(parsedTasks.count == 1 ? "" : "s") extracted")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            Divider()

            // Task list
            if filteredTasks.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(filteredTasks) { task in
                        TaskRowView(
                            task: task,
                            onToggleStatus: { toggleStatus(task) },
                            onDelete: { deleteTask(task) }
                        )
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            editingTask = task
                            showingTaskForm = true
                        }
                    }
                    .onMove(perform: reorderTasks)
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .sheet(isPresented: $showingTaskForm) {
            ManualTaskForm(
                isPresented: $showingTaskForm,
                existingTask: editingTask
            ) { task in
                saveTask(task)
            }
        }
        .onAppear(perform: loadTasks)
    }

    // MARK: - Computed

    private var filteredTasks: [TetherTask] {
        guard let filter = filterStatus else { return tasks }
        return tasks.filter { $0.status == filter }
    }

    private var taskSummary: String {
        let total = tasks.count
        let done = tasks.filter { $0.status == .done }.count
        if total == 0 { return "No tasks yet" }
        return "\(done)/\(total) completed"
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "text.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No tasks yet")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Type your plans above and Tether will extract tasks, or press \(Image(systemName: "command")) N to add manually.")
                .font(.body)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            Button("Add Task") {
                editingTask = nil
                showingTaskForm = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Parsed Task Actions

    private func acceptParsedTask(at index: Int) {
        guard parsedTasks.indices.contains(index) else { return }
        let parsed = parsedTasks[index]

        // Create or find project if specified
        var projectId: Int64?
        if let projectName = parsed.projectName {
            projectId = findOrCreateProject(name: projectName)
        }

        var task = TetherTask(
            projectId: projectId,
            title: parsed.title,
            estimateMinutes: parsed.estimateMinutes,
            priority: parsed.priority
        )
        saveTask(task)

        withAnimation(.tetherQuick) {
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
        withAnimation(.tetherQuick) {
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
            TetherLogger.general.error("Failed to find/create project: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Task Actions

    private func loadTasks() {
        do {
            tasks = try DatabaseManager.shared.fetchTasks()
        } catch {
            TetherLogger.general.error("Failed to load tasks: \(error.localizedDescription)")
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
            TetherLogger.general.error("Failed to save task: \(error.localizedDescription)")
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
            TetherLogger.general.error("Failed to delete task: \(error.localizedDescription)")
        }
    }

    private func reorderTasks(from source: IndexSet, to destination: Int) {
        var reordered = filteredTasks
        reordered.move(fromOffsets: source, toOffset: destination)
        do {
            for (index, task) in reordered.enumerated() {
                if let taskId = task.id {
                    try DatabaseManager.shared.updateTaskOrder(taskId: taskId, newOrder: index)
                }
            }
            loadTasks()
        } catch {
            TetherLogger.general.error("Failed to reorder tasks: \(error.localizedDescription)")
        }
    }
}

#Preview {
    PlanningView()
}
