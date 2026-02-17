import SwiftUI
import UmbraKit

struct ActiveSessionView: View {
    @Bindable var sessionManager: SessionManager

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Timer display
            Text(Session.formatSeconds(sessionManager.elapsedSeconds))
                .font(.system(size: 72, weight: .light, design: .monospaced))
                .foregroundStyle(sessionManager.isDistracted ? Color.umbraDistracted : .primary)
                .contentTransition(.numericText())

            // Status
            HStack(spacing: 16) {
                if sessionManager.state == .paused {
                    Label("Paused", systemImage: "pause.circle.fill")
                        .foregroundStyle(Color.umbraPaused)
                        .font(.headline)
                } else if sessionManager.isDistracted {
                    Label("Distracted — \(sessionManager.currentApp)", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.umbraDistracted)
                        .font(.headline)
                } else {
                    Label("Focused", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Color.umbraFocused)
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
                    .controlSize(.large)
                    .keyboardShortcut("p", modifiers: .command)
                } else if sessionManager.state == .paused {
                    Button(action: { sessionManager.resumeSession() }) {
                        Label("Resume", systemImage: "play.fill")
                            .frame(minWidth: 100)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut("p", modifiers: .command)
                }

                Button(action: { sessionManager.stopSession() }) {
                    Label("Stop", systemImage: "stop.fill")
                        .frame(minWidth: 100)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(Color.umbraDistracted)
                .keyboardShortcut("s", modifiers: [.command, .shift])
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
    }
}
