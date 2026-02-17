import SwiftUI

struct SocialView: View {
    @State private var selectedTab: SocialTab = .friends

    enum SocialTab: String, CaseIterable {
        case friends, groups

        var title: String {
            switch self {
            case .friends: "Friends"
            case .groups: "Groups"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Sub-tab picker
            Picker("", selection: $selectedTab) {
                ForEach(SocialTab.allCases, id: \.self) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            switch selectedTab {
            case .friends:
                FriendsListView()
            case .groups:
                GroupView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
