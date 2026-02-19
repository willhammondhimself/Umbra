import SwiftUI
import TetherKit

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
                .animation(.tetherSpring, value: selectedTab)
        }
        .frame(minWidth: 700, minHeight: 500)
        .background {
            // Keyboard shortcuts for sidebar navigation (Cmd+1 through Cmd+6)
            Group {
                Button("") { selectedTab = .plan }
                    .keyboardShortcut("1", modifiers: .command)
                Button("") { selectedTab = .session }
                    .keyboardShortcut("2", modifiers: .command)
                Button("") { selectedTab = .stats }
                    .keyboardShortcut("3", modifiers: .command)
                Button("") { selectedTab = .coach }
                    .keyboardShortcut("4", modifiers: .command)
                Button("") { selectedTab = .social }
                    .keyboardShortcut("5", modifiers: .command)
                Button("") { selectedTab = .settings }
                    .keyboardShortcut("6", modifiers: .command)
            }
            .frame(width: 0, height: 0)
            .opacity(0)
            .allowsHitTesting(false)
        }
    }
}

enum AppTab: String, CaseIterable {
    case plan, session, stats, coach, social, settings

    var title: String {
        switch self {
        case .plan: "Plan"
        case .session: "Session"
        case .stats: "Stats"
        case .coach: "Coach"
        case .social: "Social"
        case .settings: "Settings"
        }
    }

    var icon: String {
        switch self {
        case .plan: "text.badge.plus"
        case .session: "timer"
        case .stats: "chart.bar.fill"
        case .coach: "brain.head.profile"
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
        case .coach: CoachingView()
        case .social: SocialView()
        case .settings: SettingsView()
        }
    }
}

#Preview {
    ContentView()
}
