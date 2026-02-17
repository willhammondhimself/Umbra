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
        ZStack {
            Circle()
                .fill(rank <= 3 ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.1))
                .frame(width: 32, height: 32)
            Text("\(rank)")
                .font(.caption.bold())
                .foregroundStyle(rank <= 3 ? Color.accentColor : .secondary)
        }
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
