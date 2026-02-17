import SwiftUI
import Charts
import os
import UmbraKit

enum TimeRange: String, CaseIterable {
    case today = "Today"
    case thisWeek = "This Week"
    case thisMonth = "This Month"
    case last30 = "Last 30 Days"

    var dateRange: (start: Date, end: Date) {
        let calendar = Calendar.current
        let now = Date()
        let start: Date
        switch self {
        case .today:
            start = calendar.startOfDay(for: now)
        case .thisWeek:
            start = calendar.date(byAdding: .day, value: -7, to: now)!
        case .thisMonth:
            start = calendar.date(byAdding: .month, value: -1, to: now)!
        case .last30:
            start = calendar.date(byAdding: .day, value: -30, to: now)!
        }
        return (start, now)
    }
}

struct StatsView: View {
    @State private var selectedRange: TimeRange = .thisWeek
    @State private var periodStats = PeriodStats()
    @State private var dailyData: [DailyFocusPoint] = []
    @State private var distractors: [DistractorSummary] = []
    @State private var insights: [Insight] = []

    private let aggregator = StatsAggregator()
    private let insightsEngine = InsightsEngine()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Stats")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("Your productivity at a glance")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                Picker("", selection: $selectedRange) {
                    ForEach(TimeRange.allCases, id: \.self) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 350)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(spacing: 20) {
                    // Summary cards
                    summaryCards

                    // Focus chart
                    focusChart

                    // Bottom row
                    HStack(alignment: .top, spacing: 20) {
                        // Distractors
                        distractorsList

                        // Insights
                        insightsView
                    }
                }
                .padding()
            }
        }
        .onChange(of: selectedRange) { _, _ in loadData() }
        .onAppear { loadData() }
    }

    // MARK: - Summary Cards

    private var summaryCards: some View {
        HStack(spacing: 16) {
            SummaryCard(
                title: "Focused Time",
                value: Session.formatSeconds(periodStats.focusedSeconds),
                icon: "eye",
                color: .umbraFocused
            )
            SummaryCard(
                title: "Sessions",
                value: "\(periodStats.sessionCount)",
                icon: "timer",
                color: .umbraNeutral
            )
            SummaryCard(
                title: "Avg Length",
                value: Session.formatSeconds(periodStats.averageSessionLength),
                icon: "clock",
                color: Color.accentColor
            )
            SummaryCard(
                title: "Focus Rate",
                value: String(format: "%.0f%%", periodStats.focusPercentage),
                icon: "percent",
                color: .umbraPaused
            )
            SummaryCard(
                title: "Streak",
                value: "\(periodStats.currentStreak)d",
                icon: "flame",
                color: .umbraStreak
            )
        }
    }

    // MARK: - Focus Chart

    private var focusChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Daily Focus Time")
                .font(.headline)

            if dailyData.isEmpty {
                Text("No data for this period")
                    .foregroundStyle(.secondary)
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
            } else {
                Chart(dailyData) { point in
                    BarMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Minutes", point.focusedMinutes)
                    )
                    .foregroundStyle(Color.accentColor.gradient)
                    .cornerRadius(4)
                }
                .chartYAxisLabel("Minutes")
                .frame(height: 200)
            }
        }
        .padding()
        .glassCard(cornerRadius: 12)
    }

    // MARK: - Distractors

    private var distractorsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Top Distractors")
                .font(.headline)

            if distractors.isEmpty {
                Text("No distractions recorded")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 20)
            } else {
                ForEach(distractors) { d in
                    HStack {
                        Text(d.appName)
                            .font(.body)
                        Spacer()
                        Text("\(d.count)x")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Text("\(d.totalSeconds / 60)m")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .padding(.vertical, 2)
                    if d.id != distractors.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding()
        .glassCard(cornerRadius: 12)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Insights

    private var insightsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Insights")
                .font(.headline)

            if insights.isEmpty {
                Text("Complete a few sessions to see insights")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 20)
            } else {
                ForEach(insights) { insight in
                    InsightCardView(insight: insight)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Data Loading

    private func loadData() {
        let range = selectedRange.dateRange
        do {
            periodStats = try aggregator.stats(from: range.start, to: range.end)
            dailyData = try aggregator.dailyFocusData(from: range.start, to: range.end)
            distractors = try aggregator.topDistractors(from: range.start, to: range.end)
        } catch {
            UmbraLogger.general.error("Failed to load stats: \(error.localizedDescription)")
        }
        insights = insightsEngine.generateInsights()
    }
}

struct SummaryCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .glassCard(cornerRadius: 12)
    }
}

struct InsightCardView: View {
    let insight: Insight

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: insight.icon)
                .font(.title3)
                .foregroundStyle(insightColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(insight.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(insight.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(insightColor.opacity(0.08)))
    }

    private var insightColor: Color {
        switch insight.type {
        case .positive: .umbraPositive
        case .warning: .umbraWarning
        case .neutral: .umbraNeutral
        }
    }
}

#Preview {
    StatsView()
}
