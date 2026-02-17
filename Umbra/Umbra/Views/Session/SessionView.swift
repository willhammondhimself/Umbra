import SwiftUI
import os
import UmbraKit

struct SessionView: View {
    @State private var sessionManager = SessionManager.shared
    @State private var pastSessions: [Session] = []

    var body: some View {
        VStack(spacing: 0) {
            switch sessionManager.state {
            case .idle:
                idleView

            case .running, .paused:
                ActiveSessionView(sessionManager: sessionManager)

            case .summary:
                idleView
                    .onAppear {
                        if case .summary(let session) = sessionManager.state {
                            PostSessionSummaryController.shared.show(session: session)
                        }
                    }
            }
        }
        .onAppear {
            sessionManager.checkForIncompleteSession()
            loadPastSessions()
        }
    }

    private var idleView: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Session")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("Focus on what matters")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()

            Divider()

            if pastSessions.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "timer")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No sessions yet")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("Start a focus session to track your productivity and block distractions.")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)

                    Button("Start Session") {
                        sessionManager.startSession()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 16) {
                    Button("Start Session") {
                        sessionManager.startSession()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                    .padding(.top, 16)

                    // Recent sessions
                    List {
                        Section("Recent Sessions") {
                            ForEach(pastSessions) { session in
                                SessionHistoryRow(session: session)
                            }
                        }
                    }
                    .listStyle(.inset(alternatesRowBackgrounds: true))
                }
            }
        }
    }

    private func loadPastSessions() {
        do {
            pastSessions = try DatabaseManager.shared.fetchSessions(limit: 20)
                .filter { $0.isComplete }
        } catch {
            UmbraLogger.session.error("Failed to load sessions: \(error.localizedDescription)")
        }
    }
}

struct SessionHistoryRow: View {
    let session: Session

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.startTime, style: .date)
                    .font(.body)
                Text(session.startTime, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 16) {
                Label(session.formattedDuration, systemImage: "clock")
                    .font(.caption)
                    .monospacedDigit()

                Label(String(format: "%.0f%%", session.focusPercentage), systemImage: "eye")
                    .font(.caption)
                    .foregroundStyle(session.focusPercentage >= 80 ? Color.umbraFocused : Color.umbraPaused)

                Label("\(session.distractionCount)", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(session.distractionCount == 0 ? Color.umbraFocused : .secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    SessionView()
}
