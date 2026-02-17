import EventKit
import os

/// EventKit wrapper for calendar integration.
/// Provides access to user calendar events, free block detection,
/// focus session scheduling, and conflict checking.
///
/// Must remain on `@MainActor` since EventKit objects are not Sendable.
@MainActor
public final class CalendarService {
    public static let shared = CalendarService()

    private let store = EKEventStore()
    private let logger = TetherLogger.general

    /// The name used for Tether-created calendar events.
    public static let focusCalendarTitle = "Tether Focus"

    /// Minimum gap (in seconds) to consider a block "free" by default.
    public static let defaultMinFreeBlock: TimeInterval = 15 * 60 // 15 minutes

    // MARK: - Authorization

    /// Current authorization status for calendar events.
    public var authorizationStatus: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    /// Whether the app currently has full access to calendar events.
    public var isAuthorized: Bool {
        authorizationStatus == .fullAccess
    }

    /// Requests full access to calendar events.
    /// Returns `true` if access was granted.
    public func requestAccess() async -> Bool {
        do {
            let granted = try await store.requestFullAccessToEvents()
            if granted {
                logger.info("Calendar access granted")
            } else {
                logger.notice("Calendar access denied by user")
            }
            return granted
        } catch {
            logger.error("Calendar access request failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Fetch Events

    /// Fetches all calendar events in the given date range.
    /// Returns an empty array if not authorized.
    public func fetchEvents(from startDate: Date, to endDate: Date) -> [EKEvent] {
        guard isAuthorized else { return [] }

        let predicate = store.predicateForEvents(
            withStart: startDate,
            end: endDate,
            calendars: nil
        )
        return store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
    }

    /// Fetches events from specific calendars only.
    public func fetchEvents(from startDate: Date, to endDate: Date, calendars: [EKCalendar]) -> [EKEvent] {
        guard isAuthorized else { return [] }

        let predicate = store.predicateForEvents(
            withStart: startDate,
            end: endDate,
            calendars: calendars.isEmpty ? nil : calendars
        )
        return store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
    }

    // MARK: - Free Block Detection

    /// Finds gaps between events on a given date where a focus session could fit.
    ///
    /// - Parameters:
    ///   - date: The date to search (uses the full day from 8 AM to 10 PM).
    ///   - minDuration: Minimum gap duration in seconds. Defaults to 15 minutes.
    /// - Returns: An array of `DateInterval` representing free time blocks.
    public func findFreeBlocks(
        on date: Date,
        minDuration: TimeInterval = defaultMinFreeBlock
    ) -> [DateInterval] {
        guard isAuthorized else { return [] }

        let calendar = Calendar.current
        // Working hours: 8 AM to 10 PM
        guard let dayStart = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: date),
              let dayEnd = calendar.date(bySettingHour: 22, minute: 0, second: 0, of: date)
        else {
            return []
        }

        let events = fetchEvents(from: dayStart, to: dayEnd)
            .filter { !$0.isAllDay } // Exclude all-day events from blocking

        var freeBlocks: [DateInterval] = []
        var cursor = dayStart

        for event in events {
            let eventStart = max(event.startDate, dayStart)
            let eventEnd = min(event.endDate, dayEnd)

            if cursor < eventStart {
                let gap = eventStart.timeIntervalSince(cursor)
                if gap >= minDuration {
                    freeBlocks.append(DateInterval(start: cursor, end: eventStart))
                }
            }
            cursor = max(cursor, eventEnd)
        }

        // Check remaining time after last event
        if cursor < dayEnd {
            let gap = dayEnd.timeIntervalSince(cursor)
            if gap >= minDuration {
                freeBlocks.append(DateInterval(start: cursor, end: dayEnd))
            }
        }

        return freeBlocks
    }

    // MARK: - Create Focus Block

    /// Creates a calendar event for a Tether focus session.
    ///
    /// - Parameters:
    ///   - title: The event title. Defaults to "Tether Focus".
    ///   - start: Start time for the focus block.
    ///   - duration: Duration of the focus block in seconds.
    /// - Returns: The created `EKEvent`.
    /// - Throws: If the event cannot be saved.
    @discardableResult
    public func createFocusBlock(
        title: String = focusCalendarTitle,
        start: Date,
        duration: TimeInterval
    ) throws -> EKEvent {
        guard isAuthorized else {
            throw CalendarError.notAuthorized
        }

        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = start.addingTimeInterval(duration)
        event.calendar = store.defaultCalendarForNewEvents
        event.notes = "Focus session scheduled by Tether"

        // Add an alert 5 minutes before
        event.addAlarm(EKAlarm(relativeOffset: -5 * 60))

        try store.save(event, span: .thisEvent)
        logger.info("Created focus block: \(title) at \(start) for \(Int(duration / 60)) min")

        return event
    }

    // MARK: - Conflict Detection

    /// Checks for calendar events that overlap with a proposed time range.
    ///
    /// - Parameters:
    ///   - start: Proposed session start time.
    ///   - duration: Proposed session duration in seconds.
    /// - Returns: Events that conflict with the proposed time range.
    public func checkConflicts(start: Date, duration: TimeInterval) -> [EKEvent] {
        guard isAuthorized else { return [] }

        let end = start.addingTimeInterval(duration)
        return fetchEvents(from: start, to: end)
            .filter { !$0.isAllDay } // All-day events are not hard conflicts
    }

    // MARK: - Calendar List

    /// Returns all writable calendars the user has.
    public var writableCalendars: [EKCalendar] {
        guard isAuthorized else { return [] }
        return store.calendars(for: .event)
            .filter { $0.allowsContentModifications }
    }

    /// Returns all calendars the user has.
    public var allCalendars: [EKCalendar] {
        guard isAuthorized else { return [] }
        return store.calendars(for: .event)
    }

    // MARK: - Errors

    public enum CalendarError: LocalizedError {
        case notAuthorized
        case saveFailed(String)

        public var errorDescription: String? {
            switch self {
            case .notAuthorized:
                "Calendar access is not authorized. Please grant access in System Settings."
            case .saveFailed(let reason):
                "Failed to save calendar event: \(reason)"
            }
        }
    }
}
