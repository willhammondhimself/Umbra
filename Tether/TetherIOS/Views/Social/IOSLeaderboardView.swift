import SwiftUI
import TetherKit

struct IOSLeaderboardView: View {
    let groupId: UUID
    let groupName: String

    @State private var entries: [LeaderboardEntryItem] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading leaderboard...")
            } else if entries.isEmpty {
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

                        VStack(alignment: .trailing, spacing: 2) {
                            Text(formatFocusTime(entry.focusedSeconds))
                                .font(.headline)
                            Text("\(entry.sessionCount) sessions")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Rank \(entry.rank): \(entry.displayName ?? "Anonymous")")
                    .accessibilityValue("\(formatFocusTime(entry.focusedSeconds)), \(entry.sessionCount) sessions")
                }
            }
        }
        .navigationTitle(groupName)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await loadLeaderboard()
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
            .if(rank <= 3) { $0.tintedGlass(Color.accentColor.opacity(0.15), cornerRadius: 16) }
            .if(rank > 3) { $0.glassCard(cornerRadius: 16) }
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
        isLoading = entries.isEmpty
        defer { isLoading = false }
        do {
            entries = try await APIClient.shared.request(.groupLeaderboard(groupId))
        } catch {
            // Non-critical
        }
    }
}
