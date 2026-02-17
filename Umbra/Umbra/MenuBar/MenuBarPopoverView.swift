import SwiftUI

struct MenuBarPopoverView: View {
    @State private var sessionManager = SessionManager.shared
    @State private var syncManager = SyncManager.shared

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Image(systemName: "timer")
                    .foregroundStyle(Color.accentColor)
                Text("Umbra")
                    .font(.headline)
                Spacer()
                syncIndicator
            }
            .padding(.bottom, 4)

            Divider()

            switch sessionManager.state {
            case .idle:
                idleContent

            case .running, .paused:
                activeContent

            case .summary:
                summaryContent
            }

            Divider()

            // Open main window
            Button("Open Umbra") {
                NSApp.activate(ignoringOtherApps: true)
                if let window = NSApp.windows.first(where: { $0.title == "Umbra" || $0.isKeyWindow }) {
                    window.makeKeyAndOrderFront(nil)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .font(.caption)
        }
        .padding()
        .frame(width: 280)
    }

    // MARK: - Idle

    private var idleContent: some View {
        VStack(spacing: 12) {
            todayStats

            Button("Start Session") {
                sessionManager.startSession()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
    }

    // MARK: - Active Session

    private var activeContent: some View {
        VStack(spacing: 12) {
            // Timer
            Text(Session.formatSeconds(sessionManager.elapsedSeconds))
                .font(.system(size: 36, weight: .light, design: .monospaced))
                .foregroundStyle(sessionManager.isDistracted ? .red : .primary)

            // Status
            HStack(spacing: 16) {
                if sessionManager.state == .paused {
                    Text("Paused")
                        .foregroundStyle(.orange)
                        .font(.caption)
                } else if sessionManager.isDistracted {
                    Text("Distracted")
                        .foregroundStyle(.red)
                        .font(.caption)
                } else {
                    Text("Focused")
                        .foregroundStyle(.green)
                        .font(.caption)
                }

                Text("\(sessionManager.distractionCount) distractions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Controls
            HStack(spacing: 12) {
                if sessionManager.state == .running {
                    Button("Pause") { sessionManager.pauseSession() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                } else if sessionManager.state == .paused {
                    Button("Resume") { sessionManager.resumeSession() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }

                Button("Stop") { sessionManager.stopSession() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.red)
            }
        }
    }

    // MARK: - Summary

    private var summaryContent: some View {
        VStack(spacing: 8) {
            Text("Session Complete")
                .font(.subheadline)
                .fontWeight(.medium)

            Button("Dismiss") {
                sessionManager.dismissSummary()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    // MARK: - Today Stats

    private var todayStats: some View {
        VStack(spacing: 8) {
            let stats = todayPeriodStats

            HStack {
                VStack {
                    Text(Session.formatSeconds(stats.focusedSeconds))
                        .font(.title3)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                    Text("Focused")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                Divider().frame(height: 30)

                VStack {
                    Text("\(stats.sessionCount)")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text("Sessions")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                Divider().frame(height: 30)

                VStack {
                    Text("\(stats.currentStreak)d")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text("Streak")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Sync Indicator

    private var syncIndicator: some View {
        HStack(spacing: 4) {
            if !syncManager.isOnline {
                Image(systemName: "wifi.slash")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                Text("Offline")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            } else if syncManager.isSyncing {
                ProgressView()
                    .controlSize(.mini)
                Text("Syncing")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "checkmark.icloud")
                    .font(.caption2)
                    .foregroundStyle(.green)
                Text("Synced")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var todayPeriodStats: PeriodStats {
        let agg = StatsAggregator()
        let start = Calendar.current.startOfDay(for: Date())
        return (try? agg.stats(from: start, to: Date())) ?? PeriodStats()
    }
}
