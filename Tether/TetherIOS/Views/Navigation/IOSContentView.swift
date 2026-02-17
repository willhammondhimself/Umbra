import SwiftUI
import TetherKit

struct IOSContentView: View {
    @State private var selectedTab: IOSTab = .session

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Plan", systemImage: "text.badge.plus", value: .plan) {
                NavigationStack {
                    IOSTaskListView()
                        .navigationTitle("Plan")
                }
            }

            Tab("Session", systemImage: "timer", value: .session) {
                NavigationStack {
                    IOSSessionView()
                        .navigationTitle("Session")
                }
            }

            Tab("Stats", systemImage: "chart.bar.fill", value: .stats) {
                NavigationStack {
                    IOSStatsView()
                        .navigationTitle("Stats")
                }
            }

            Tab("Coach", systemImage: "brain.head.profile", value: .coach) {
                NavigationStack {
                    IOSCoachingView()
                        .navigationTitle("Coach")
                }
            }

            Tab("Social", systemImage: "person.2", value: .social) {
                NavigationStack {
                    IOSSocialView()
                        .navigationTitle("Social")
                }
            }

            Tab("Settings", systemImage: "gearshape", value: .settings) {
                NavigationStack {
                    IOSSettingsView()
                        .navigationTitle("Settings")
                }
            }
        }
    }
}

enum IOSTab: String {
    case plan, session, stats, coach, social, settings
}
