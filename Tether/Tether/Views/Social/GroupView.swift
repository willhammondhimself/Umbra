import SwiftUI
import os
import TetherKit

struct GroupView: View {
    @State private var groups: [GroupItem] = []

    var body: some View {
        if groups.isEmpty {
            ContentUnavailableView(
                "No Groups Yet",
                systemImage: "person.3",
                description: Text("Groups let you compete on leaderboards with friends.")
            )
            .task {
                await loadGroups()
            }
        } else {
            List(groups) { group in
                NavigationLink {
                    LeaderboardView(groupId: group.id, groupName: group.name)
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(group.name)
                                .font(.headline)
                            Text("\(group.memberCount) members")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "trophy")
                            .foregroundStyle(Color.accentColor)
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityLabel("\(group.name), \(group.memberCount) members")
            }
            .task {
                await loadGroups()
            }
        }
    }

    private func loadGroups() async {
        do {
            groups = try await APIClient.shared.request(.groups)
        } catch {
            TetherLogger.social.error("Failed to load groups: \(error.localizedDescription)")
        }
    }
}
