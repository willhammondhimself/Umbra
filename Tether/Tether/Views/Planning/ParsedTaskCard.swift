import SwiftUI
import TetherKit

struct ParsedTaskCard: View {
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
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Discard")
            }

            if isEditing {
                TextField("Task title", text: $parsedTask.title)
                    .textFieldStyle(.roundedBorder)
            } else {
                Text(parsedTask.title)
                    .font(.body)
                    .fontWeight(.medium)
            }

            HStack(spacing: 12) {
                // Priority picker
                Picker("Priority", selection: $parsedTask.priority) {
                    ForEach(TetherTask.Priority.allCases, id: \.self) { p in
                        Label(p.label, systemImage: p.iconName).tag(p)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()

                // Estimate
                if let est = parsedTask.estimateMinutes {
                    Label(formatMinutes(est), systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Project
                if let project = parsedTask.projectName {
                    Label(project, systemImage: "folder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(isEditing ? "Done" : "Edit") {
                    isEditing.toggle()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(Color.accentColor)

                Button("Add", action: onAccept)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.background)
                .shadow(color: .black.opacity(0.06), radius: 3, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
        )
    }

    private func formatMinutes(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)m" }
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }
}
