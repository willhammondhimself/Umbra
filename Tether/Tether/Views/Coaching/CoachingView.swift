import SwiftUI
import TetherKit

struct CoachingView: View {
    @State private var nudge: CoachingNudge?
    @State private var goals: AIGoalsResponse?
    @State private var heatmap: [HeatmapEntry] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let coachingService = AICoachingService.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Coach")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("AI-powered productivity insights")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                Button {
                    Task { await refreshAll() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.body)
                }
                .buttonStyle(.bordered)
                .disabled(isLoading)
            }
            .padding()

            Divider()

            if isLoading && nudge == nil {
                loadingView
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        // Coaching nudge card
                        nudgeCard

                        // AI goals section
                        goalsSection

                        // Focus heatmap
                        heatmapSection
                    }
                    .padding()
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .font(.title2)
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
        .glassCard(cornerRadius: TetherRadius.card)
    }

    // MARK: - Goals Section

    private var goalsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "target")
                    .font(.title2)
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
                    goalRow(goal, index: index)
                }
            } else if goals != nil {
                Text("Complete a few sessions to get personalized goal suggestions.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                Text("Unable to load goal suggestions.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: TetherRadius.card)
    }

    @ViewBuilder
    private func goalRow(_ goal: AIGoal, index: Int) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(index + 1)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Color.accentColor, in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(goal.goal)
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack(spacing: 4) {
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
        .padding(.vertical, 4)

        if index < (goals?.goals.count ?? 0) - 1 {
            Divider()
        }
    }

    // MARK: - Heatmap Section

    private var heatmapSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "square.grid.3x3.fill")
                    .font(.title2)
                    .foregroundStyle(Color.tetherNeutral)
                Text("Focus Heatmap")
                    .font(.headline)
                Spacer()
            }

            if heatmap.isEmpty {
                Text("Complete a few sessions to see your focus patterns.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                heatmapGrid
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: TetherRadius.card)
    }

    private var heatmapGrid: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Day labels
            HStack(spacing: 0) {
                Text("")
                    .frame(width: 40)
                ForEach(dayLabels, id: \.self) { day in
                    Text(day)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            // Hour rows (show every 2 hours for readability)
            ForEach(Array(stride(from: 6, to: 24, by: 2)), id: \.self) { hour in
                HStack(spacing: 2) {
                    Text(hourLabel(hour))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)

                    ForEach(0..<7, id: \.self) { day in
                        let minutes = focusMinutes(hour: hour, day: day)
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(heatmapColor(minutes: minutes))
                            .frame(maxWidth: .infinity)
                            .frame(height: 20)
                            .help(String(format: "%@ %@: %.0f min", dayLabels[day], hourLabel(hour), minutes))
                    }
                }
            }

            // Legend
            HStack(spacing: 4) {
                Spacer()
                Text("Less")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                ForEach([0.0, 15.0, 30.0, 60.0, 120.0], id: \.self) { value in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(heatmapColor(minutes: value))
                        .frame(width: 12, height: 12)
                }
                Text("More")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Offline Badge

    private var offlineBadge: some View {
        Label("Offline", systemImage: "wifi.slash")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.quaternary, in: Capsule())
    }

    // MARK: - Heatmap Helpers

    private let dayLabels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    private func hourLabel(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "ha"
        var components = DateComponents()
        components.hour = hour
        let date = Calendar.current.date(from: components) ?? Date()
        return formatter.string(from: date).lowercased()
    }

    private func focusMinutes(hour: Int, day: Int) -> Double {
        // Aggregate the two hours in this cell (hour and hour+1)
        let entries = heatmap.filter { entry in
            (entry.hour == hour || entry.hour == hour + 1) && entry.dayOfWeek == day
        }
        return entries.reduce(0) { $0 + $1.focusedMinutes }
    }

    private func heatmapColor(minutes: Double) -> Color {
        if minutes <= 0 {
            return Color.secondary.opacity(0.08)
        } else if minutes < 15 {
            return Color.accentColor.opacity(0.2)
        } else if minutes < 30 {
            return Color.accentColor.opacity(0.4)
        } else if minutes < 60 {
            return Color.accentColor.opacity(0.6)
        } else {
            return Color.accentColor.opacity(0.85)
        }
    }

    // MARK: - Data Loading

    private func refreshAll() async {
        isLoading = true
        errorMessage = nil

        async let nudgeResult = coachingService.getCoachingNudge()
        async let goalsResult = coachingService.getAIGoals()
        async let heatmapResult = coachingService.getHeatmap()

        do {
            let fetchedNudge = try await nudgeResult
            let fetchedGoals = try await goalsResult
            let fetchedHeatmap = try await heatmapResult

            nudge = fetchedNudge
            goals = fetchedGoals
            heatmap = fetchedHeatmap
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

#Preview {
    CoachingView()
}
