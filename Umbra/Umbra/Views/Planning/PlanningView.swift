import SwiftUI
import UmbraKit

struct PlanningView: View {
    @State private var tasks: [UmbraTask] = []
    @State private var showingTaskForm = false
    @State private var editingTask: UmbraTask?
    @State private var filterStatus: UmbraTask.Status?

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
                    Text("All").tag(nil as UmbraTask.Status?)
                    ForEach(UmbraTask.Status.allCases, id: \.self) { status in
                        Text(status.label).tag(status as UmbraTask.Status?)
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
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
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

    private var filteredTasks: [UmbraTask] {
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
            Text("Type your plans above and Umbra will extract tasks, or press \(Image(systemName: "command")) N to add manually.")
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

        var task = UmbraTask(
            projectId: projectId,
            title: parsed.title,
            estimateMinutes: parsed.estimateMinutes,
            priority: parsed.priority
        )
        saveTask(task)

        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            parsedTasks.remove(at: index)
        }
    }

    private func acceptAllParsedTasks() {
        for parsed in parsedTasks {
            var projectId: Int64?
            if let projectName = parsed.projectName {
                projectId = findOrCreateProject(name: projectName)
            }

            let task = UmbraTask(
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
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
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
            print("Failed to find/create project: \(error)")
            return nil
        }
    }

    // MARK: - Task Actions

    private func loadTasks() {
        do {
            tasks = try DatabaseManager.shared.fetchTasks()
        } catch {
            print("Failed to load tasks: \(error)")
        }
    }

    private func saveTask(_ task: UmbraTask) {
        do {
            var mutableTask = task
            if mutableTask.id == nil {
                mutableTask.sortOrder = try DatabaseManager.shared.nextSortOrder(projectId: mutableTask.projectId)
            }
            try DatabaseManager.shared.saveTask(&mutableTask)
            loadTasks()
        } catch {
            print("Failed to save task: \(error)")
        }
    }

    private func toggleStatus(_ task: UmbraTask) {
        var updated = task
        switch task.status {
        case .todo: updated.status = .done
        case .inProgress: updated.status = .done
        case .done: updated.status = .todo
        }
        saveTask(updated)
    }

    private func deleteTask(_ task: UmbraTask) {
        do {
            try DatabaseManager.shared.deleteTask(task)
            loadTasks()
        } catch {
            print("Failed to delete task: \(error)")
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
            print("Failed to reorder tasks: \(error)")
        }
    }
}

#Preview {
    PlanningView()
}
