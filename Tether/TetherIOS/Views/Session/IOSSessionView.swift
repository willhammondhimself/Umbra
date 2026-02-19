import SwiftUI
import EventKit
import TetherKit

struct IOSSessionView: View {
    @State private var sessionManager = IOSSessionManager.shared
    @State private var pastSessions: [Session] = []
    @State private var upcomingEvents: [EKEvent] = []
    @State private var conflictingEvents: [EKEvent] = []
    @State private var showConflictWarning = false
    @Environment(\.scenePhase) private var scenePhase

    private let calendarService = CalendarService.shared

    var body: some View {
        Group {
            switch sessionManager.state {
            case .idle:
                idleView
            case .running, .paused:
                IOSActiveSessionView(sessionManager: sessionManager)
            case .summary(let session):
                IOSSummaryView(session: session) {
                    sessionManager.dismissSummary()
                    loadPastSessions()
                } onNewSession: {
                    sessionManager.dismissSummary()
                    startSessionWithConflictCheck()
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            sessionManager.handleScenePhaseChange(isActive: newPhase == .active)
            if newPhase == .active {
                refreshUpcomingEvents()
            }
        }
        .onAppear {
            sessionManager.checkForIncompleteSession()
            loadPastSessions()
            refreshUpcomingEvents()
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
            if pastSessions.isEmpty && upcomingEvents.isEmpty {
                ContentUnavailableView {
                    Label("No Sessions", systemImage: "timer")
                } description: {
                    Text("Start a focus session to track your productivity.")
                } actions: {
                    Button("Start Session") {
                        startSessionWithConflictCheck()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            } else {
                List {
                    Section {
                        Button("Start Session") {
                            startSessionWithConflictCheck()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                    }

                    // Upcoming calendar events
                    if !upcomingEvents.isEmpty {
                        Section("Upcoming Events") {
                            ForEach(upcomingEvents, id: \.eventIdentifier) { event in
                                IOSCalendarEventRow(event: event)
                            }
                        }
                    }

                    Section("Recent Sessions") {
                        ForEach(pastSessions) { session in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(session.startTime, style: .date)
                                        .font(.body)
                                    Text(session.startTime, style: .time)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                HStack(spacing: 12) {
                                    Label(session.formattedDuration, systemImage: "clock")
                                        .font(.caption)
                                        .monospacedDigit()

                                    Label(String(format: "%.0f%%", session.focusPercentage), systemImage: "eye")
                                        .font(.caption)
                                        .foregroundStyle(session.focusPercentage >= 80 ? Color.tetherFocused : Color.tetherPaused)
                                }
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Session on \(session.startTime.formatted(date: .abbreviated, time: .shortened))")
                            .accessibilityValue("Duration \(session.formattedDuration), \(String(format: "%.0f", session.focusPercentage)) percent focused")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func startSessionWithConflictCheck() {
        guard calendarService.isAuthorized else {
            sessionManager.startSession()
            return
        }

        let conflicts = calendarService.checkConflicts(start: Date(), duration: 60 * 60)
        if conflicts.isEmpty {
            sessionManager.startSession()
        } else {
            conflictingEvents = conflicts
            showConflictWarning = true
        }
    }

    private func refreshUpcomingEvents() {
        guard calendarService.isAuthorized else { return }
        let now = Date()
        let calendar = Calendar.current
        let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: now) ?? now
        upcomingEvents = calendarService.fetchEvents(from: now, to: endOfDay)
            .filter { !$0.isAllDay }
            .prefix(5)
            .map { $0 }
    }

    private func loadPastSessions() {
        do {
            pastSessions = try DatabaseManager.shared.fetchSessions(limit: 20)
                .filter { $0.isComplete }
        } catch {
            // Non-critical
        }
    }
}

// MARK: - iOS Calendar Event Row

struct IOSCalendarEventRow: View {
    let event: EKEvent

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(cgColor: event.calendar.cgColor))
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title ?? "Untitled")
                    .font(.body)
                    .lineLimit(1)
                Text(timeRange)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(event.title ?? "Untitled"), \(timeRange)")
    }

    private var timeRange: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        let start = formatter.string(from: event.startDate)
        let end = formatter.string(from: event.endDate)
        return "\(start) - \(end)"
    }
}

// MARK: - Active Session View

struct IOSActiveSessionView: View {
    @Bindable var sessionManager: IOSSessionManager

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Timer
            Text(Session.formatSeconds(sessionManager.elapsedSeconds))
                .font(TetherFont.timerHero)
                .contentTransition(.numericText())
                .accessibilityLabel("Session timer")
                .accessibilityValue(Session.formatSeconds(sessionManager.elapsedSeconds))

            // Status
            if sessionManager.state == .paused {
                Label("Paused", systemImage: "pause.circle.fill")
                    .foregroundStyle(Color.tetherPaused)
                    .font(.headline)
            } else {
                Label("Focused", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Color.tetherFocused)
                    .font(.headline)
            }

            // Stats
            HStack(spacing: 32) {
                VStack(spacing: 4) {
                    Text(Session.formatSeconds(sessionManager.focusedSeconds))
                        .font(.title3)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                    Text("Focused")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Focused time")
                .accessibilityValue(Session.formatSeconds(sessionManager.focusedSeconds))

                VStack(spacing: 4) {
                    Text("\(sessionManager.distractionCount)")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text("Distractions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Distractions")
                .accessibilityValue("\(sessionManager.distractionCount)")
            }

            Spacer()

            // Controls
            HStack(spacing: 16) {
                if sessionManager.state == .running {
                    Button(action: { sessionManager.pauseSession() }) {
                        Label("Pause", systemImage: "pause.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .buttonStyle(.tetherPressable)
                    .controlSize(.large)
                    .accessibilityHint("Pause the current focus session")
                } else if sessionManager.state == .paused {
                    Button(action: { sessionManager.resumeSession() }) {
                        Label("Resume", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonStyle(.tetherPressable)
                    .controlSize(.large)
                    .accessibilityHint("Resume the paused focus session")
                }

                Button(action: { sessionManager.stopSession() }) {
                    Label("Stop", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .buttonStyle(.tetherPressable)
                .controlSize(.large)
                .tint(Color.tetherDistracted)
                .accessibilityHint("End the focus session and view summary")
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
    }
}

// MARK: - Summary View

struct IOSSummaryView: View {
    let session: Session
    var onDismiss: () -> Void
    var onNewSession: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(TetherFont.iconHeroSmall)
                .foregroundStyle(Color.tetherFocused)

            Text("Session Complete")
                .font(.title)
                .fontWeight(.bold)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                summaryCard(icon: "clock", label: "Total", value: session.formattedDuration)
                summaryCard(icon: "eye", label: "Focused", value: session.formattedFocused)
                summaryCard(icon: "percent", label: "Rate", value: String(format: "%.0f%%", session.focusPercentage))
                summaryCard(icon: "exclamationmark.triangle", label: "Distractions", value: "\(session.distractionCount)")
            }
            .padding(.horizontal)

            Spacer()

            VStack(spacing: 12) {
                Button("Start New Session") {
                    onNewSession()
                }
                .buttonStyle(.borderedProminent)
                .buttonStyle(.tetherPressable)
                .controlSize(.large)
                .frame(maxWidth: .infinity)

                Button("Done") {
                    onDismiss()
                }
                .buttonStyle(.bordered)
                .buttonStyle(.tetherPressable)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
    }

    @ViewBuilder
    private func summaryCard(icon: String, label: String, value: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, TetherSpacing.md)
        .glassCard(cornerRadius: TetherRadius.button)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
}
