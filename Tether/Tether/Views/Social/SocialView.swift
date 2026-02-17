import SwiftUI
import TetherKit

struct SocialView: View {
    var body: some View {
        VStack(spacing: 0) {
            FriendsListView()

            Divider()

            // Groups coming soon placeholder
            HStack(spacing: 8) {
                Image(systemName: "person.3")
                    .foregroundStyle(.secondary)
                Text("Groups & Leaderboards coming soon")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
