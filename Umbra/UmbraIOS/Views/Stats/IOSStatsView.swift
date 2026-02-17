import SwiftUI
import Charts
import UmbraKit

enum IOSTimeRange: String, CaseIterable {
    case today = "Today"
    case week = "Week"
    case month = "Month"
    case thirtyDays = "30 Days"

    var dateRange: (start: Date, end: Date) {
        let calendar = Calendar.current
        let now = Date()
        let start: Date
        switch self {
        case .today: start = calendar.startOfDay(for: now)
        case .week: start = calendar.date(byAdding: .day, value: -7, to: now)!
        case .month: start = calendar.date(byAdding: .month, value: -1, to: now)!
        case .thirtyDays: start = calendar.date(byAdding: .day, value: -30, to: now)!
        }
        return (start, now)
    }
}

struct IOSStatsView: View {
    @State private var selectedRange: IOSTimeRange = .week
    @State private var periodStats = PeriodStats()
    @State private var dailyData: [DailyFocusPoint] = []
    @State private var distractors: [DistractorSummary] = []
    @State private var insights: [Insight] = []

    private let aggregator = StatsAggregator()
    private let insightsEngine = InsightsEngine()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Time range picker
                Picker("Range", selection: $selectedRange) {
                    ForEach(IOSTimeRange.allCases, id: \.self) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                // Summary cards
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                ], spacing: 12) {
                    IOSSummaryCard(
                        title: "Focused",
                        value: Session.formatSeconds(periodStats.focusedSeconds),
                        icon: "eye",
                        color: Color.umbraFocused
                    )
                    IOSSummaryCard(
                        title: "Sessions",
                        value: "\(periodStats.sessionCount)",
                        icon: "timer",
                        color: Color.umbraNeutral
                    )
                    IOSSummaryCard(
                        title: "Avg Length",
                        value: Session.formatSeconds(periodStats.averageSessionLength),
                        icon: "clock",
                        color: .purple
                    )
                    IOSSummaryCard(
                        title: "Focus Rate",
                        value: String(format: "%.0f%%", periodStats.focusPercentage),
                        icon: "percent",
                        color: Color.umbraPaused
                    )
                    IOSSummaryCard(
                        title: "Streak",
                        value: "\(periodStats.currentStreak)d",
                        icon: "flame",
                        color: Color.umbraStreak
                    )
                    IOSSummaryCard(
                        title: "Distractions",
                        value: "\(periodStats.distractionCount)",
                        icon: "exclamationmark.triangle",
                        color: Color.umbraDistracted
                    )
                }
                .padding(.horizontal)

                // Chart
                VStack(alignment: .leading, spacing: 8) {
                    Text("Daily Focus Time")
                        .font(.headline)
                        .padding(.horizontal)

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
                        .padding(.horizontal)
                    }
                }

                // Top Distractors
                if !distractors.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Top Distractors")
                            .font(.headline)
                            .padding(.horizontal)

                        ForEach(distractors) { d in
                            HStack {
                                Text(d.appName)
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
                            .padding(.horizontal)
                        }
                    }
                }

                // Insights
                if !insights.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Insights")
                            .font(.headline)
                            .padding(.horizontal)

                        ForEach(insights) { insight in
                            HStack(spacing: 10) {
                                Image(systemName: insight.icon)
                                    .foregroundStyle(insightColor(insight.type))
                                    .frame(width: 24)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(insight.title)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    Text(insight.message)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 6)
                        }
                    }
                }
            }
            .padding(.vertical)
        }
        .onChange(of: selectedRange) { _, _ in loadData() }
        .onAppear { loadData() }
    }

    private func insightColor(_ type: Insight.InsightType) -> Color {
        switch type {
        case .positive: Color.umbraFocused
        case .warning: Color.umbraPaused
        case .neutral: Color.umbraNeutral
        }
    }

    private func loadData() {
        let range = selectedRange.dateRange
        do {
            periodStats = try aggregator.stats(from: range.start, to: range.end)
            dailyData = try aggregator.dailyFocusData(from: range.start, to: range.end)
            distractors = try aggregator.topDistractors(from: range.start, to: range.end)
        } catch {
            // Non-critical
        }
        insights = insightsEngine.generateInsights()
    }
}

struct IOSSummaryCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}
