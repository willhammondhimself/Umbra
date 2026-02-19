import SwiftUI
import os
import TetherKit

struct LeaderboardView: View {
    let groupId: UUID
    let groupName: String

    @State private var entries: [LeaderboardEntryItem] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(groupName)
                .font(.title2.bold())
                .padding(.horizontal)

            Text("Weekly Focused Time")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            if entries.isEmpty {
                ContentUnavailableView(
                    "No Data",
                    systemImage: "chart.bar",
                    description: Text("Complete focus sessions to appear on the leaderboard.")
                )
            } else {
                List(entries) { entry in
                    HStack {
                        rankBadge(entry.rank)

                        Text(entry.displayName ?? "Anonymous")
                            .font(.body)

                        Spacer()

                        VStack(alignment: .trailing) {
                            Text(formatFocusTime(entry.focusedSeconds))
                                .font(.headline)
                            Text("\(entry.sessionCount) sessions")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Rank \(entry.rank): \(entry.displayName ?? "Anonymous")")
                    .accessibilityValue("\(formatFocusTime(entry.focusedSeconds)), \(entry.sessionCount) sessions")
                }
            }
        }
        .task {
            await loadLeaderboard()
        }
    }

    @ViewBuilder
    private func rankBadge(_ rank: Int) -> some View {
        Text("\(rank)")
            .font(.caption.bold())
            .foregroundStyle(rank <= 3 ? Color.accentColor : .secondary)
            .frame(width: 32, height: 32)
            .if(rank <= 3) { view in
                view.tintedGlass(Color.accentColor.opacity(0.15), cornerRadius: 16)
            }
            .if(rank > 3) { view in
                view.glassCard(cornerRadius: 16)
            }
            .accessibilityLabel("Rank \(rank)")
    }

    private func formatFocusTime(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    private func loadLeaderboard() async {
        do {
            entries = try await APIClient.shared.request(.groupLeaderboard(groupId))
        } catch {
            TetherLogger.social.error("Failed to load leaderboard: \(error.localizedDescription)")
        }
    }
}
