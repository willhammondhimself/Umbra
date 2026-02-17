import SwiftUI
import TetherKit

struct PostSessionSummaryView: View {
    let session: Session
    let streak: Int
    var onNewSession: () -> Void
    var onDismiss: () -> Void

    @State private var aiSummary: SessionSummary?
    @State private var isLoadingSummary = false

    var body: some View {
        VStack(spacing: 16) {
            // Header
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.tetherFocused)

            Text("Session Complete")
                .font(.title)
                .fontWeight(.bold)

            // Stats grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
            ], spacing: 16) {
                summaryCard(
                    icon: "clock",
                    label: "Total Time",
                    value: session.formattedDuration,
                    color: Color.tetherNeutral
                )

                summaryCard(
                    icon: "eye",
                    label: "Focused",
                    value: session.formattedFocused,
                    color: Color.tetherFocused
                )

                summaryCard(
                    icon: "percent",
                    label: "Focus Rate",
                    value: String(format: "%.0f%%", session.focusPercentage),
                    color: session.focusPercentage >= 80 ? Color.tetherFocused : Color.tetherPaused
                )

                summaryCard(
                    icon: "exclamationmark.triangle",
                    label: "Distractions",
                    value: "\(session.distractionCount)",
                    color: session.distractionCount == 0 ? Color.tetherFocused : Color.tetherDistracted
                )
            }

            // Streak
            if streak > 1 {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(Color.tetherStreak)
                    Text("\(streak) day streak!")
                        .font(.headline)
                        .foregroundStyle(Color.tetherStreak)
                }
                .padding(.vertical, 2)
            }

            // AI Coach Summary
            aiCoachSection

            Spacer(minLength: 4)

            // Actions
            HStack(spacing: 12) {
                Button("Done") {
                    onDismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .keyboardShortcut(.escape, modifiers: [])

                Button("Start New Session") {
                    onNewSession()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(.top, 36)
        .padding([.bottom, .leading, .trailing], 28)
        .frame(width: 480, height: 480)
        .glassEffect(in: .rect(cornerRadius: TetherRadius.card))
        .task {
            await loadAISummary()
        }
    }

    // MARK: - AI Coach Section

    @ViewBuilder
    private var aiCoachSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "brain.head.profile")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                Text("AI Coach")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.accentColor)
                Spacer()
                if let aiSummary, !aiSummary.isAiGenerated {
                    Text("Offline")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if isLoadingSummary {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Generating insight...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let aiSummary {
                Text(aiSummary.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.06), in: .rect(cornerRadius: TetherRadius.small))
    }

    // MARK: - AI Summary Loading

    private func loadAISummary() async {
        guard let remoteId = session.remoteId else {
            // No remote ID means the session hasn't synced yet; show a fallback
            aiSummary = SessionSummary(
                summary: "Sync this session to get an AI-powered summary.",
                isAiGenerated: false
            )
            return
        }

        isLoadingSummary = true
        do {
            aiSummary = try await AICoachingService.shared.getSessionSummary(sessionId: remoteId)
        } catch {
            aiSummary = SessionSummary(
                summary: "Session complete. Review your stats above for details.",
                isAiGenerated: false
            )
        }
        isLoadingSummary = false
    }

    @ViewBuilder
    private func summaryCard(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)

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
        .glassEffect(in: .rect(cornerRadius: TetherRadius.button))
    }
}
