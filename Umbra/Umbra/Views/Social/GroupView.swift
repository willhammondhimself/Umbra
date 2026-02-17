import SwiftUI
import UmbraKit

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
                    }
                }
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
            print("Failed to load groups: \(error)")
        }
    }
}

struct GroupItem: Identifiable, Codable {
    let id: UUID
    let name: String
    let createdBy: UUID
    let createdAt: Date
    let memberCount: Int

    enum CodingKeys: String, CodingKey {
        case id, name
        case createdBy = "created_by"
        case createdAt = "created_at"
        case memberCount = "member_count"
    }
}
