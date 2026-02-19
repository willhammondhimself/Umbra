import SwiftUI
import EventKit
import TetherKit

/// Compact sidebar view showing today's calendar events, free blocks, and
/// a quick "Schedule Focus" action. Designed for the macOS detail area or
/// as a supplementary panel next to the Session view.
struct CalendarSidebarView: View {
    @State private var isAuthorized = false
    @State private var upcomingEvents: [EKEvent] = []
    @State private var freeBlocks: [DateInterval] = []
    @State private var isRequestingAccess = false
    @State private var showScheduleSheet = false
    @State private var selectedFreeBlock: DateInterval?

    private let calendarService = CalendarService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Label("Calendar", systemImage: "calendar")
                    .font(.headline)
                Spacer()
                if isAuthorized {
                    Button {
                        refreshCalendarData()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Refresh calendar data")
                    .accessibilityLabel("Refresh calendar")
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)

            Divider()

            if isAuthorized {
                authorizedContent
            } else {
                permissionPrompt
            }
        }
        .frame(minWidth: 260)
        .onAppear {
            isAuthorized = calendarService.isAuthorized
            if isAuthorized {
                refreshCalendarData()
            }
        }
        .sheet(isPresented: $showScheduleSheet) {
            ScheduleFocusSheet(
                freeBlock: selectedFreeBlock,
                onSchedule: { title, start, duration in
                    scheduleFocusBlock(title: title, start: start, duration: duration)
                }
            )
        }
    }

    // MARK: - Authorized Content

    private var authorizedContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Upcoming events
                if !upcomingEvents.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Upcoming Today")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)

                        ForEach(upcomingEvents, id: \.eventIdentifier) { event in
                            CalendarEventRow(event: event)
                        }
                    }
                } else {
                    HStack {
                        Image(systemName: "checkmark.circle")
                            .foregroundStyle(Color.tetherFocused)
                        Text("No more events today")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                // Free blocks
                if !freeBlocks.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Available for Focus")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)

                        ForEach(freeBlocks, id: \.start) { block in
                            FreeBlockRow(block: block) {
                                selectedFreeBlock = block
                                showScheduleSheet = true
                            }
                        }
                    }
                } else if !upcomingEvents.isEmpty {
                    HStack {
                        Image(systemName: "calendar.badge.exclamationmark")
                            .foregroundStyle(Color.tetherWarning)
                        Text("No free blocks found today")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                // Quick schedule button
                Button {
                    selectedFreeBlock = nil
                    showScheduleSheet = true
                } label: {
                    Label("Schedule Focus Block", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
            .padding()
        }
    }

    // MARK: - Permission Prompt

    private var permissionPrompt: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("Calendar Access")
                .font(.headline)

            Text("Tether can check your calendar to suggest optimal focus times and avoid scheduling conflicts.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Grant Access") {
                Task {
                    isRequestingAccess = true
                    let granted = await calendarService.requestAccess()
                    isRequestingAccess = false
                    isAuthorized = granted
                    if granted {
                        refreshCalendarData()
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRequestingAccess)

            if calendarService.authorizationStatus == .denied {
                Text("Access was previously denied. Open System Settings > Privacy & Security > Calendars to enable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Data

    private func refreshCalendarData() {
        let now = Date()
        let calendar = Calendar.current
        let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: now) ?? now

        upcomingEvents = calendarService.fetchEvents(from: now, to: endOfDay)
            .filter { !$0.isAllDay }

        freeBlocks = calendarService.findFreeBlocks(on: now)
            .filter { $0.end > now } // Only future free blocks
    }

    private func scheduleFocusBlock(title: String, start: Date, duration: TimeInterval) {
        do {
            try calendarService.createFocusBlock(title: title, start: start, duration: duration)
            refreshCalendarData()
        } catch {
            TetherLogger.general.error("Failed to create focus block: \(error.localizedDescription)")
        }
    }
}

// MARK: - Calendar Event Row

struct CalendarEventRow: View {
    let event: EKEvent

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color(cgColor: event.calendar.cgColor))
                .frame(width: 4, height: 36)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title ?? "Untitled")
                    .font(.subheadline)
                    .lineLimit(1)
                Text(timeRange)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer()
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(event.title ?? "Untitled"), \(timeRange)")
    }

    private var timeRange: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        let start = formatter.string(from: event.startDate)
        let end = formatter.string(from: event.endDate)
        return "\(start) - \(end)"
    }
}

// MARK: - Free Block Row

struct FreeBlockRow: View {
    let block: DateInterval
    let onSchedule: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.tetherFocused.opacity(0.4))
                .frame(width: 4, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(durationText)
                    .font(.subheadline)
                    .foregroundStyle(Color.tetherFocused)
                Text(timeRange)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer()

            Button {
                onSchedule()
            } label: {
                Image(systemName: "plus.circle")
                    .font(.body)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .help("Schedule focus session in this block")
            .accessibilityLabel("Schedule focus session, \(durationText), \(timeRange)")
        }
        .padding(.vertical, 2)
    }

    private var durationText: String {
        let minutes = Int(block.duration / 60)
        if minutes >= 60 {
            let hours = minutes / 60
            let remaining = minutes % 60
            return remaining > 0 ? "\(hours)h \(remaining)m free" : "\(hours)h free"
        }
        return "\(minutes)m free"
    }

    private var timeRange: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        let start = formatter.string(from: block.start)
        let end = formatter.string(from: block.end)
        return "\(start) - \(end)"
    }
}

// MARK: - Schedule Focus Sheet

struct ScheduleFocusSheet: View {
    let freeBlock: DateInterval?
    let onSchedule: (String, Date, TimeInterval) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = "Tether Focus"
    @State private var startDate: Date
    @State private var durationMinutes: Double = 60

    init(freeBlock: DateInterval?, onSchedule: @escaping (String, Date, TimeInterval) -> Void) {
        self.freeBlock = freeBlock
        self.onSchedule = onSchedule
        let defaultStart = freeBlock?.start ?? Date().addingTimeInterval(5 * 60)
        _startDate = State(initialValue: defaultStart)
        if let block = freeBlock {
            let blockMinutes = block.duration / 60
            _durationMinutes = State(initialValue: min(blockMinutes, 60))
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Schedule Focus Block")
                .font(.title3)
                .fontWeight(.semibold)

            Form {
                TextField("Title", text: $title)
                DatePicker("Start", selection: $startDate)
                    .datePickerStyle(.field)

                HStack {
                    Text("Duration")
                    Spacer()
                    Slider(value: $durationMinutes, in: 15...180, step: 15)
                        .frame(width: 150)
                    Text("\(Int(durationMinutes))m")
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Schedule") {
                    onSchedule(title, startDate, durationMinutes * 60)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
    }
}

#Preview {
    CalendarSidebarView()
        .frame(width: 300, height: 500)
}
