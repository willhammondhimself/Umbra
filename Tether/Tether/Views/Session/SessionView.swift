import SwiftUI
import EventKit
import os
import TetherKit

struct SessionView: View {
    @State private var sessionManager = SessionManager.shared
    @State private var pastSessions: [Session] = []
    @State private var conflictingEvents: [EKEvent] = []
    @State private var showConflictWarning = false

    private let calendarService = CalendarService.shared

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
        .alert("Calendar Conflict", isPresented: $showConflictWarning) {
            Button("Start Anyway") {
                sessionManager.startSession()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            let eventNames = conflictingEvents
                .compactMap { $0.title }
                .joined(separator: ", ")
            Text("You have overlapping events: \(eventNames). Start session anyway?")
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
                TetherEmptyStateView(
                    systemImage: "timer",
                    title: "No sessions yet",
                    subtitle: "Start a focus session to track your productivity and block distractions.",
                    actionLabel: "Start Session"
                ) {
                    startSessionWithConflictCheck()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            } else {
                VStack(spacing: 16) {
                    Button("Start Session") {
                        startSessionWithConflictCheck()
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonStyle(.tetherPressable)
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

    // MARK: - Actions

    private func startSessionWithConflictCheck() {
        guard calendarService.isAuthorized else {
            // No calendar access: start without checking
            sessionManager.startSession()
            return
        }

        // Check for conflicts in the next 60 minutes
        let conflicts = calendarService.checkConflicts(start: Date(), duration: 60 * 60)
        if conflicts.isEmpty {
            sessionManager.startSession()
        } else {
            conflictingEvents = conflicts
            showConflictWarning = true
        }
    }

    private func loadPastSessions() {
        do {
            pastSessions = try DatabaseManager.shared.fetchSessions(limit: 20)
                .filter { $0.isComplete }
        } catch {
            TetherLogger.session.error("Failed to load sessions: \(error.localizedDescription)")
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
                    .foregroundStyle(session.focusPercentage >= 80 ? Color.tetherFocused : Color.tetherPaused)

                Label("\(session.distractionCount)", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(session.distractionCount == 0 ? Color.tetherFocused : .secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Session on \(session.startTime.formatted(date: .abbreviated, time: .shortened))")
        .accessibilityValue("Duration \(session.formattedDuration), \(String(format: "%.0f", session.focusPercentage)) percent focused, \(session.distractionCount) distractions")
    }
}

#Preview {
    SessionView()
}
