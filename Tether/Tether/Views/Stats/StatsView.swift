import SwiftUI
import AppKit
import Charts
import os
import TetherKit

enum TimeRange: CaseIterable, Hashable {
    case today
    case thisWeek
    case thisMonth
    case last7
    case last30
    case custom

    var title: String {
        switch self {
        case .today: "Today"
        case .thisWeek: "This Week"
        case .thisMonth: "This Month"
        case .last7: "Last 7 Days"
        case .last30: "Last 30 Days"
        case .custom: "Custom Range"
        }
    }

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
        case .last7:
            start = calendar.date(byAdding: .day, value: -7, to: now)!
        case .last30:
            start = calendar.date(byAdding: .day, value: -30, to: now)!
        case .custom:
            // Custom dates are managed by StatsView state
            start = calendar.startOfDay(for: now)
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
    @State private var previousStats = PeriodStats()
    @State private var customStart: Date = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var customEnd: Date = Date()
    @State private var exportError: String?
    @State private var showExportError = false

    private let aggregator = StatsAggregator()
    private let insightsEngine = InsightsEngine()
    private let exporter = DataExporter()

    private var effectiveDateRange: (start: Date, end: Date) {
        if selectedRange == .custom {
            return (customStart, customEnd)
        }
        return selectedRange.dateRange
    }

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

                exportMenu

                Picker("", selection: $selectedRange) {
                    ForEach(TimeRange.allCases, id: \.self) { range in
                        Text(range.title).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 450)
                .accessibilityLabel("Time range")
                .accessibilityValue(selectedRange.title)
            }
            .padding()

            // Custom date pickers
            if selectedRange == .custom {
                HStack(spacing: 16) {
                    Spacer()
                    DatePicker("From:", selection: $customStart, displayedComponents: .date)
                        .labelsHidden()
                        .accessibilityLabel("Start date")
                    Text("to")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    DatePicker("To:", selection: $customEnd, displayedComponents: .date)
                        .labelsHidden()
                        .accessibilityLabel("End date")
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            Divider()

            ScrollView {
                VStack(spacing: 20) {
                    // Summary cards
                    summaryCards

                    // Comparison badges
                    comparisonRow

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
        .onChange(of: customStart) { _, _ in
            if selectedRange == .custom { loadData() }
        }
        .onChange(of: customEnd) { _, _ in
            if selectedRange == .custom { loadData() }
        }
        .onAppear { loadData() }
        .alert("Export Error", isPresented: $showExportError) {
            Button("OK") {}
        } message: {
            Text(exportError ?? "An unknown error occurred.")
        }
    }

    // MARK: - Export Menu

    private var exportMenu: some View {
        Menu {
            Button("Export Sessions (CSV)") {
                performExport(suggestedName: "tether-sessions.csv") {
                    let range = effectiveDateRange
                    return try exporter.exportSessions(format: .csv, from: range.start, to: range.end)
                }
            }
            Button("Export Sessions (JSON)") {
                performExport(suggestedName: "tether-sessions.json") {
                    let range = effectiveDateRange
                    return try exporter.exportSessions(format: .json, from: range.start, to: range.end)
                }
            }
            Divider()
            Button("Export Tasks (CSV)") {
                performExport(suggestedName: "tether-tasks.csv") {
                    try exporter.exportTasks(format: .csv)
                }
            }
            Button("Export Tasks (JSON)") {
                performExport(suggestedName: "tether-tasks.json") {
                    try exporter.exportTasks(format: .json)
                }
            }
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("Export data")
    }

    // MARK: - Summary Cards

    private var summaryCards: some View {
        HStack(spacing: 16) {
            SummaryCard(
                title: "Focused Time",
                value: Session.formatSeconds(periodStats.focusedSeconds),
                icon: "eye",
                color: .tetherFocused
            )
            SummaryCard(
                title: "Sessions",
                value: "\(periodStats.sessionCount)",
                icon: "timer",
                color: .tetherNeutral
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
                color: .tetherPaused
            )
            SummaryCard(
                title: "Streak",
                value: "\(periodStats.currentStreak)d",
                icon: "flame",
                color: .tetherStreak
            )
        }
    }

    // MARK: - Comparison Row

    private var comparisonRow: some View {
        HStack(spacing: 16) {
            ComparisonBadge(
                title: "Focused Time",
                current: Double(periodStats.focusedSeconds),
                previous: Double(previousStats.focusedSeconds)
            )
            ComparisonBadge(
                title: "Sessions",
                current: Double(periodStats.sessionCount),
                previous: Double(previousStats.sessionCount)
            )
            ComparisonBadge(
                title: "Focus Rate",
                current: periodStats.focusPercentage,
                previous: previousStats.focusPercentage
            )
        }
        .padding()
        .glassCard(cornerRadius: 12)
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
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(d.appName): \(d.count) times, \(d.totalSeconds / 60) minutes")
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
        .padding()
        .glassCard(cornerRadius: 12)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Data Loading

    private func loadData() {
        let range = effectiveDateRange
        do {
            periodStats = try aggregator.stats(from: range.start, to: range.end)
            dailyData = try aggregator.dailyFocusData(from: range.start, to: range.end)
            distractors = try aggregator.topDistractors(from: range.start, to: range.end)
            let comparison = try aggregator.comparisonStats(for: range)
            previousStats = comparison.previous
        } catch {
            TetherLogger.general.error("Failed to load stats: \(error.localizedDescription)")
        }
        insights = insightsEngine.generateInsights()
    }

    // MARK: - Export Helpers

    private func performExport(suggestedName: String, _ dataProvider: () throws -> Data) {
        do {
            let data = try dataProvider()
            exportData(data, suggestedName: suggestedName)
        } catch {
            exportError = error.localizedDescription
            showExportError = true
        }
    }

    private func exportData(_ data: Data, suggestedName: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.begin { response in
            if response == .OK, let url = panel.url {
                try? data.write(to: url)
            }
        }
    }
}

// MARK: - Comparison Badge

struct ComparisonBadge: View {
    let title: String
    let current: Double
    let previous: Double

    private var percentageChange: Double {
        guard previous > 0 else {
            return current > 0 ? 100 : 0
        }
        return ((current - previous) / previous) * 100
    }

    private var isImprovement: Bool {
        percentageChange > 0
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            if abs(percentageChange) < 0.1 {
                Image(systemName: "minus")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("No change")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: isImprovement ? "arrow.up.right" : "arrow.down.right")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(isImprovement ? Color.tetherPositive : Color.tetherDistracted)
                Text(String(format: "%+.0f%%", percentageChange))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(isImprovement ? Color.tetherPositive : Color.tetherDistracted)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) comparison")
        .accessibilityValue(abs(percentageChange) < 0.1 ? "No change" : String(format: "%+.0f percent", percentageChange))
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)")
        .accessibilityValue(value)
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
        .tintedGlass(insightColor.opacity(0.15), cornerRadius: TetherRadius.small)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(insight.title): \(insight.message)")
    }

    private var insightColor: Color {
        switch insight.type {
        case .positive: .tetherPositive
        case .warning: .tetherWarning
        case .neutral: .tetherNeutral
        }
    }
}

#Preview {
    StatsView()
}
