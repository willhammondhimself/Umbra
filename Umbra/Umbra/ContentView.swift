import SwiftUI
import UmbraKit

struct ContentView: View {
    @AppStorage("selectedTab") private var selectedTab: AppTab = .plan
    @State private var isSidebarExpanded = false

    var body: some View {
        NavigationSplitView {
            SidebarView(selectedTab: $selectedTab, isExpanded: $isSidebarExpanded)
                .navigationSplitViewColumnWidth(
                    min: 56,
                    ideal: isSidebarExpanded ? 200 : 56,
                    max: 200
                )
        } detail: {
            selectedTab.view
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.umbraSpring, value: selectedTab)
        }
        .frame(minWidth: 700, minHeight: 500)
    }
}

enum AppTab: String, CaseIterable {
    case plan, session, stats, social, settings

    var title: String {
        switch self {
        case .plan: "Plan"
        case .session: "Session"
        case .stats: "Stats"
        case .social: "Social"
        case .settings: "Settings"
        }
    }

    var icon: String {
        switch self {
        case .plan: "text.badge.plus"
        case .session: "timer"
        case .stats: "chart.bar.fill"
        case .social: "person.2"
        case .settings: "gearshape"
        }
    }

    @MainActor @ViewBuilder
    var view: some View {
        switch self {
        case .plan: PlanningView()
        case .session: SessionView()
        case .stats: StatsView()
        case .social: SocialView()
        case .settings: SettingsView()
        }
    }
}

#Preview {
    ContentView()
}
