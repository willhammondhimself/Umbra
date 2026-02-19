import SwiftUI
import TetherKit

struct IOSCoachingView: View {
    @State private var nudge: CoachingNudge?
    @State private var goals: AIGoalsResponse?
    @State private var isLoading = true

    private let coachingService = AICoachingService.shared

    var body: some View {
        Group {
            if isLoading && nudge == nil {
                loadingView
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        // Coaching nudge card
                        nudgeCard

                        // AI goals section
                        goalsSection
                    }
                    .padding()
                }
                .refreshable {
                    await refreshAll()
                }
            }
        }
        .task {
            await refreshAll()
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Loading coaching insights...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Nudge Card

    private var nudgeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                Text("Today's Insight")
                    .font(.headline)
                Spacer()
                if let nudge, !nudge.isAiGenerated {
                    offlineBadge
                }
            }

            if let nudge {
                Text(nudge.nudge)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Unable to load coaching insight.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: TetherRadius.sidebar)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Today's Insight: \(nudge?.nudge ?? "No insight available")")
    }

    // MARK: - Goals Section

    private var goalsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "target")
                    .font(.title3)
                    .foregroundStyle(Color.tetherPositive)
                Text("AI Goal Suggestions")
                    .font(.headline)
                Spacer()
                if let goals, !goals.isAiGenerated {
                    offlineBadge
                }
            }

            if let goals, !goals.goals.isEmpty {
                ForEach(Array(goals.goals.enumerated()), id: \.offset) { index, goal in
                    goalRow(goal, index: index, isLast: index == goals.goals.count - 1)
                }
            } else if goals != nil {
                Text("Complete a few sessions to get personalized goal suggestions.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                Text("Unable to load goal suggestions.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: TetherRadius.sidebar)
    }

    @ViewBuilder
    private func goalRow(_ goal: AIGoal, index: Int, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(index + 1)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color.accentColor, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(goal.goal)
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack(spacing: 3) {
                    Image(systemName: "flag.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.tetherPositive)
                    Text("Target: \(goal.target)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(goal.reasoning)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Goal \(index + 1): \(goal.goal). Target: \(goal.target). \(goal.reasoning)")

        if !isLast {
            Divider()
        }
    }

    // MARK: - Offline Badge

    private var offlineBadge: some View {
        Label("Offline", systemImage: "wifi.slash")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .glassPill()
    }

    // MARK: - Data Loading

    private func refreshAll() async {
        isLoading = true

        async let nudgeResult = coachingService.getCoachingNudge()
        async let goalsResult = coachingService.getAIGoals()

        do {
            let fetchedNudge = try await nudgeResult
            let fetchedGoals = try await goalsResult

            nudge = fetchedNudge
            goals = fetchedGoals
        } catch {
            // Errors handled gracefully by the service with fallback values
        }

        isLoading = false
    }
}

#Preview {
    NavigationStack {
        IOSCoachingView()
            .navigationTitle("Coach")
    }
}
