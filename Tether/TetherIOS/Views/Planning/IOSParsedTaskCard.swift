import SwiftUI
import TetherKit

struct IOSParsedTaskCard: View {
    @Binding var parsedTask: ParsedTask
    var onAccept: () -> Void
    var onDiscard: () -> Void

    @State private var isEditing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.accentColor)
                    .font(.caption)
                Text("Extracted Task")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: onDiscard) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            if isEditing {
                TextField("Task title", text: $parsedTask.title)
                    .textFieldStyle(.roundedBorder)
            } else {
                Text(parsedTask.title)
                    .font(.body)
                    .fontWeight(.medium)
            }

            HStack(spacing: 8) {
                // Priority badge
                Text(parsedTask.priority.label)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(priorityColor.opacity(0.15), in: .capsule)
                    .foregroundStyle(priorityColor)

                if let est = parsedTask.estimateMinutes {
                    Label(formatMinutes(est), systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let project = parsedTask.projectName {
                    Label(project, systemImage: "folder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            HStack {
                Button(isEditing ? "Done" : "Edit") {
                    isEditing.toggle()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Button("Add", action: onAccept)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.background)
                .shadow(color: .black.opacity(0.06), radius: 3, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
        )
    }

    private var priorityColor: Color {
        switch parsedTask.priority {
        case .urgent, .high: Color.tetherDistracted
        case .medium: Color.accentColor
        case .low: Color.tetherNeutral
        }
    }

    private func formatMinutes(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)m" }
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }
}
