import SwiftUI
import TetherKit

struct FloatingWidgetView: View {
    @State private var sessionManager = SessionManager.shared
    @State private var isExpanded = false
    @State private var tasks: [TetherTask] = []

    var body: some View {
        Group {
            if isExpanded {
                expandedView
            } else {
                collapsedView
            }
        }
        .onHover { hovering in
            withAnimation(.tetherSpring) {
                isExpanded = hovering
            }
        }
        .onAppear(perform: loadTasks)
    }

    // MARK: - Collapsed Pill (~220x48)

    private var collapsedView: some View {
        HStack(spacing: 10) {
            statusIcon
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 20, height: 20)

            Text(Session.formatSeconds(sessionManager.elapsedSeconds))
                .font(.system(size: 16, weight: .medium, design: .monospaced))
                .contentTransition(.numericText())

            if sessionManager.distractionCount > 0 {
                Text("\(sessionManager.distractionCount)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.tetherDistracted, in: .capsule)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(in: .capsule)
        .frame(width: 220, height: 48)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Session timer")
        .accessibilityValue("\(Session.formatSeconds(sessionManager.elapsedSeconds)), \(sessionManager.distractionCount) distractions")
    }

    // MARK: - Expanded View (~300x400)

    private var expandedView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Timer + status
            HStack {
                statusIcon
                    .font(.system(size: 16, weight: .semibold))

                Text(Session.formatSeconds(sessionManager.elapsedSeconds))
                    .font(.system(size: 28, weight: .light, design: .monospaced))
                    .contentTransition(.numericText())

                Spacer()
            }

            Divider()

            // Status label
            statusLabel
                .font(.subheadline)

            // Stats row
            HStack(spacing: 20) {
                Label(Session.formatSeconds(sessionManager.focusedSeconds), systemImage: "eye")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Label("\(sessionManager.distractionCount)", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(sessionManager.distractionCount == 0 ? Color.tetherFocused : Color.tetherDistracted)
            }

            Divider()

            // Task checklist
            if !tasks.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tasks")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(tasks.prefix(5)) { task in
                        HStack(spacing: 6) {
                            Image(systemName: task.status == .done ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 12))
                                .foregroundStyle(task.status == .done ? Color.tetherFocused : .secondary)

                            Text(task.title)
                                .font(.caption)
                                .lineLimit(1)
                                .strikethrough(task.status == .done)
                                .foregroundStyle(task.status == .done ? .secondary : .primary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(task.title)
                        .accessibilityValue(task.status == .done ? "Completed" : "To do")
                    }
                }
            }

            Spacer(minLength: 4)

            // Controls
            HStack(spacing: 8) {
                if sessionManager.state == .running {
                    Button(action: { sessionManager.pauseSession() }) {
                        Image(systemName: "pause.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("Pause session")
                } else if sessionManager.state == .paused {
                    Button(action: { sessionManager.resumeSession() }) {
                        Image(systemName: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .accessibilityLabel("Resume session")
                }

                Button(action: { sessionManager.stopSession() }) {
                    Image(systemName: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.red)
                .accessibilityLabel("Stop session")
            }
        }
        .padding(16)
        .frame(width: 280, height: 360)
        .glassEffect(in: .rect(cornerRadius: TetherRadius.card))
    }

    // MARK: - Helpers

    @ViewBuilder
    private var statusIcon: some View {
        let color = Color.forSessionStatus(
            sessionManager.isDistracted,
            isPaused: sessionManager.state == .paused
        )
        Image(systemName: statusIconName)
            .foregroundStyle(color)
    }

    private var statusIconName: String {
        if sessionManager.state == .paused { return "pause.circle.fill" }
        if sessionManager.isDistracted { return "exclamationmark.triangle.fill" }
        return "checkmark.circle.fill"
    }

    @ViewBuilder
    private var statusLabel: some View {
        if sessionManager.state == .paused {
            Label("Paused", systemImage: "pause.circle.fill")
                .foregroundStyle(Color.tetherPaused)
        } else if sessionManager.isDistracted {
            Label(sessionManager.currentApp, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.tetherDistracted)
        } else {
            Label("Focused", systemImage: "checkmark.circle.fill")
                .foregroundStyle(Color.tetherFocused)
        }
    }

    private func loadTasks() {
        do {
            tasks = try DatabaseManager.shared.fetchTasks()
                .filter { $0.status != .done }
        } catch {
            // Non-critical — widget still works without task list
        }
    }
}
