import SwiftUI
import UmbraKit

struct IOSSessionView: View {
    @State private var sessionManager = IOSSessionManager.shared
    @State private var pastSessions: [Session] = []
    @Environment(\.scenePhase) private var scenePhase

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
                    sessionManager.startSession()
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            sessionManager.handleScenePhaseChange(isActive: newPhase == .active)
        }
        .onAppear {
            sessionManager.checkForIncompleteSession()
            loadPastSessions()
        }
    }

    private var idleView: some View {
        VStack(spacing: 0) {
            if pastSessions.isEmpty {
                ContentUnavailableView {
                    Label("No Sessions", systemImage: "timer")
                } description: {
                    Text("Start a focus session to track your productivity.")
                } actions: {
                    Button("Start Session") {
                        sessionManager.startSession()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            } else {
                List {
                    Section {
                        Button("Start Session") {
                            sessionManager.startSession()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
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
                                        .foregroundStyle(session.focusPercentage >= 80 ? Color.umbraFocused : Color.umbraPaused)
                                }
                            }
                        }
                    }
                }
            }
        }
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

// MARK: - Active Session View

struct IOSActiveSessionView: View {
    @Bindable var sessionManager: IOSSessionManager

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Timer
            Text(Session.formatSeconds(sessionManager.elapsedSeconds))
                .font(.system(size: 64, weight: .light, design: .monospaced))
                .contentTransition(.numericText())

            // Status
            if sessionManager.state == .paused {
                Label("Paused", systemImage: "pause.circle.fill")
                    .foregroundStyle(Color.umbraPaused)
                    .font(.headline)
            } else {
                Label("Focused", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Color.umbraFocused)
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

                VStack(spacing: 4) {
                    Text("\(sessionManager.distractionCount)")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text("Distractions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
                    .controlSize(.large)
                } else if sessionManager.state == .paused {
                    Button(action: { sessionManager.resumeSession() }) {
                        Label("Resume", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                Button(action: { sessionManager.stopSession() }) {
                    Label("Stop", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(.red)
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
                .font(.system(size: 56))
                .foregroundStyle(Color.umbraFocused)

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
                .controlSize(.large)
                .frame(maxWidth: .infinity)

                Button("Done") {
                    onDismiss()
                }
                .buttonStyle(.bordered)
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
        .padding(.vertical, 12)
    }
}
