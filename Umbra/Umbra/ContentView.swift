import SwiftUI

struct ContentView: View {
    @State private var selectedTab: AppTab = .plan

    var body: some View {
        TabView(selection: $selectedTab) {
            PlanningView()
                .tabItem {
                    Label(AppTab.plan.title, systemImage: AppTab.plan.icon)
                }
                .tag(AppTab.plan)

            SessionView()
                .tabItem {
                    Label(AppTab.session.title, systemImage: AppTab.session.icon)
                }
                .tag(AppTab.session)

            StatsView()
                .tabItem {
                    Label(AppTab.stats.title, systemImage: AppTab.stats.icon)
                }
                .tag(AppTab.stats)

            SocialView()
                .tabItem {
                    Label(AppTab.social.title, systemImage: AppTab.social.icon)
                }
                .tag(AppTab.social)

            SettingsView()
                .tabItem {
                    Label(AppTab.settings.title, systemImage: AppTab.settings.icon)
                }
                .tag(AppTab.settings)
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
}

#Preview {
    ContentView()
}
