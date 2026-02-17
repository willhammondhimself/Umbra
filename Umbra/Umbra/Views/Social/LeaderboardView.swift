import SwiftUI
import UmbraKit

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
                }
            }
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
        do {
            entries = try await APIClient.shared.request(.groupLeaderboard(groupId))
        } catch {
            print("Failed to load leaderboard: \(error)")
        }
    }
}

struct LeaderboardEntryItem: Identifiable, Codable {
    var id: UUID { userId }
    let userId: UUID
    let displayName: String?
    let focusedSeconds: Int
    let sessionCount: Int
    let rank: Int

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case displayName = "display_name"
        case focusedSeconds = "focused_seconds"
        case sessionCount = "session_count"
        case rank
    }
}
