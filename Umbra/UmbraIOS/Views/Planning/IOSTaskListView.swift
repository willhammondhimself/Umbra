import SwiftUI
import UmbraKit

/// Read-only task list synced from backend. Full implementation in Phase 3.8.
struct IOSTaskListView: View {
    @State private var tasks: [UmbraTask] = []
    @State private var isRefreshing = false

    var body: some View {
        List {
            if tasks.isEmpty {
                ContentUnavailableView(
                    "No Tasks",
                    systemImage: "text.badge.plus",
                    description: Text("Tasks created on macOS will appear here.")
                )
            } else {
                ForEach(tasks) { task in
                    HStack(spacing: 10) {
                        Image(systemName: task.status == .done ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(task.status == .done ? Color.umbraFocused : .secondary)

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
                }
            }
        }
        .refreshable {
            await refresh()
        }
        .onAppear(perform: loadTasks)
    }

    @ViewBuilder
    private func priorityBadge(_ priority: UmbraTask.Priority) -> some View {
        if priority != .medium {
            Text(priorityLabel(priority))
                .font(.caption2)
                .fontWeight(.semibold)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    priority >= .high ? Color.umbraDistracted.opacity(0.15) : Color.umbraNeutral.opacity(0.15),
                    in: .capsule
                )
                .foregroundStyle(priority >= .high ? Color.umbraDistracted : Color.umbraNeutral)
        }
    }

    private func priorityLabel(_ priority: UmbraTask.Priority) -> String {
        switch priority {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        case .urgent: "Urgent"
        }
    }

    private func loadTasks() {
        do {
            tasks = try DatabaseManager.shared.fetchTasks()
        } catch {
            // Non-critical
        }
    }

    private func refresh() async {
        SyncManager.shared.triggerSync()
        // Brief delay for sync to complete
        try? await Task.sleep(for: .seconds(1))
        loadTasks()
    }
}
