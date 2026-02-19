import SwiftUI
import TetherKit

struct ActiveSessionView: View {
    @Bindable var sessionManager: SessionManager

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Timer display
            Text(Session.formatSeconds(sessionManager.elapsedSeconds))
                .font(.system(size: 72, weight: .light, design: .monospaced))
                .foregroundStyle(sessionManager.isDistracted ? Color.tetherDistracted : .primary)
                .contentTransition(.numericText())
                .accessibilityLabel("Session timer")
                .accessibilityValue(Session.formatSeconds(sessionManager.elapsedSeconds))

            // Status
            HStack(spacing: 16) {
                if sessionManager.state == .paused {
                    Label("Paused", systemImage: "pause.circle.fill")
                        .foregroundStyle(Color.tetherPaused)
                        .font(.headline)
                } else if sessionManager.isDistracted {
                    Label("Distracted — \(sessionManager.currentApp)", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.tetherDistracted)
                        .font(.headline)
                } else {
                    Label("Focused", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Color.tetherFocused)
                        .font(.headline)
                }
            }

            // Stats row
            HStack(spacing: 32) {
                StatBadge(
                    icon: "eye",
                    label: "Focused",
                    value: Session.formatSeconds(sessionManager.focusedSeconds)
                )

                StatBadge(
                    icon: "exclamationmark.triangle",
                    label: "Distractions",
                    value: "\(sessionManager.distractionCount)"
                )
            }

            Spacer()

            // Controls
            HStack(spacing: 16) {
                if sessionManager.state == .running {
                    Button(action: { sessionManager.pauseSession() }) {
                        Label("Pause", systemImage: "pause.fill")
                            .frame(minWidth: 100)
                    }
                    .buttonStyle(.bordered)
                    .buttonStyle(.tetherPressable)
                    .controlSize(.large)
                    .keyboardShortcut("p", modifiers: .command)
                    .accessibilityHint("Pause the current focus session")
                } else if sessionManager.state == .paused {
                    Button(action: { sessionManager.resumeSession() }) {
                        Label("Resume", systemImage: "play.fill")
                            .frame(minWidth: 100)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonStyle(.tetherPressable)
                    .controlSize(.large)
                    .keyboardShortcut("p", modifiers: .command)
                    .accessibilityHint("Resume the paused focus session")
                }

                Button(action: { sessionManager.stopSession() }) {
                    Label("Stop", systemImage: "stop.fill")
                        .frame(minWidth: 100)
                }
                .buttonStyle(.bordered)
                .buttonStyle(.tetherPressable)
                .controlSize(.large)
                .tint(Color.tetherDistracted)
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .accessibilityHint("End the focus session and view summary")
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

struct StatBadge: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .glassCard(cornerRadius: 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
}
