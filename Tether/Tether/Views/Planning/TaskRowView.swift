import SwiftUI
import TetherKit

struct TaskRowView: View {
    let task: TetherTask
    var onToggleStatus: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Status toggle
            Button(action: {
                withAnimation(.tetherQuick) {
                    onToggleStatus()
                }
            }) {
                Image(systemName: statusIcon)
                    .font(.title3)
                    .foregroundStyle(statusColor)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.tetherPressable)
            .help(task.status == .done ? "Mark as to do" : "Mark as done")
            .accessibilityLabel(task.status == .done ? "Mark as to do" : "Mark as done")
            .accessibilityValue(task.status == .done ? "Completed" : task.status == .inProgress ? "In progress" : "To do")

            // Task content
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.body)
                    .strikethrough(task.status == .done)
                    .foregroundStyle(task.status == .done ? .secondary : .primary)

                HStack(spacing: 8) {
                    // Priority badge
                    Label(task.priority.label, systemImage: task.priority.iconName)
                        .font(.caption)
                        .foregroundStyle(priorityColor)

                    // Estimate
                    if let estimate = task.formattedEstimate {
                        Label(estimate, systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // Delete button
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(0.5)
            .help("Delete task")
            .accessibilityLabel("Delete \(task.title)")
            .accessibilityHint("Permanently removes this task")
        }
        .padding(.vertical, 4)
    }

    private var statusIcon: String {
        switch task.status {
        case .todo: "circle"
        case .inProgress: "circle.lefthalf.filled"
        case .done: "checkmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch task.status {
        case .todo: .secondary
        case .inProgress: Color.accentColor
        case .done: .green
        }
    }

    private var priorityColor: Color {
        switch task.priority {
        case .low: .secondary
        case .medium: .blue
        case .high: .orange
        case .urgent: .red
        }
    }
}
