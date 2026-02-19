import SwiftUI
import EventKit
import SafariServices
import TetherKit
import Foundation

struct SettingsView: View {
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Settings")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("Configure Tether to work for you")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()

            Divider()

            HSplitView {
                VStack(spacing: 0) {
                    // Blocklist editor
                    BlocklistEditorView()

                    Divider()

                    // Safari Extension status
                    SafariExtensionStatusView()
                        .padding()

                    Divider()

                    // Calendar settings
                    CalendarSettingsView()
                        .padding()
                }
                .frame(minWidth: 300)

                VStack(spacing: 0) {
                    // Account settings
                    AccountSettingsView()

                    Divider()

                    // Privacy settings
                    PrivacySettingsView()
                        .padding()

                    Divider()

                    // Third-party integrations
                    IntegrationsView()
                }
                .frame(minWidth: 300)
            }
        }
    }
}

// MARK: - Calendar Settings

struct CalendarSettingsView: View {
    @State private var isAuthorized = false
    @State private var autoBlockEnabled = false
    @State private var selectedCalendarIds: Set<String> = []
    @State private var availableCalendars: [EKCalendar] = []
    @State private var isRequestingAccess = false

    @AppStorage("calendarAutoBlock") private var calendarAutoBlock = false
    @AppStorage("calendarSelectedIds") private var calendarSelectedIdsData: Data = Data()

    private let calendarService = CalendarService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Calendar", systemImage: "calendar")
                .font(.headline)

            // Access toggle
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Calendar Access")
                        .font(.subheadline)
                    Text(statusDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isAuthorized {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                            .accessibilityHidden(true)
                        Text("Connected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Calendar connected")
                } else {
                    Button("Connect") {
                        Task {
                            isRequestingAccess = true
                            let granted = await calendarService.requestAccess()
                            isRequestingAccess = false
                            isAuthorized = granted
                            if granted {
                                loadCalendars()
                            }
                        }
                    }
                    .controlSize(.small)
                    .disabled(isRequestingAccess)
                }
            }

            if isAuthorized {
                Divider()

                // Auto-block toggle
                Toggle(isOn: $calendarAutoBlock) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-create calendar blocks")
                            .font(.subheadline)
                        Text("Automatically add a calendar event when you start a focus session")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                // Calendar picker
                if !availableCalendars.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Check for conflicts in:")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        ForEach(availableCalendars, id: \.calendarIdentifier) { calendar in
                            HStack(spacing: 8) {
                                let isSelected = selectedCalendarIds.contains(calendar.calendarIdentifier)
                                Button {
                                    toggleCalendar(calendar.calendarIdentifier)
                                } label: {
                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                                }
                                .buttonStyle(.plain)

                                Circle()
                                    .fill(Color(cgColor: calendar.cgColor))
                                    .frame(width: 8, height: 8)

                                Text(calendar.title)
                                    .font(.subheadline)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            isAuthorized = calendarService.isAuthorized
            if isAuthorized {
                loadCalendars()
                loadSelectedCalendarIds()
            }
        }
    }

    private var statusDescription: String {
        switch calendarService.authorizationStatus {
        case .fullAccess:
            "Tether can read your calendar to detect conflicts"
        case .denied, .restricted:
            "Open System Settings > Privacy & Security > Calendars to enable"
        case .notDetermined:
            "Allow Tether to check your calendar for scheduling conflicts"
        case .writeOnly:
            "Full access required. Update in System Settings > Privacy & Security > Calendars"
        @unknown default:
            "Calendar access status unknown"
        }
    }

    private func loadCalendars() {
        availableCalendars = calendarService.allCalendars
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private func loadSelectedCalendarIds() {
        if let ids = try? JSONDecoder().decode(Set<String>.self, from: calendarSelectedIdsData) {
            selectedCalendarIds = ids
        } else {
            // Default: select all calendars
            selectedCalendarIds = Set(availableCalendars.map(\.calendarIdentifier))
            saveSelectedCalendarIds()
        }
    }

    private func toggleCalendar(_ id: String) {
        if selectedCalendarIds.contains(id) {
            selectedCalendarIds.remove(id)
        } else {
            selectedCalendarIds.insert(id)
        }
        saveSelectedCalendarIds()
    }

    private func saveSelectedCalendarIds() {
        if let data = try? JSONEncoder().encode(selectedCalendarIds) {
            calendarSelectedIdsData = data
        }
    }
}

// MARK: - Safari Extension Status

struct SafariExtensionStatusView: View {
    private var safariExtensionBundleIdentifier: String {
        let baseBundleIdentifier = Bundle.main.bundleIdentifier ?? "com.willhammond.tether"
        return "\(baseBundleIdentifier).safari"
    }

    @State private var isEnabled = false
    @State private var isChecking = true
    @State private var extensionErrorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Safari Extension", systemImage: "safari")
                .font(.headline)

            HStack {
                Circle()
                    .fill(isEnabled ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(isEnabled ? "Enabled" : "Not Enabled")
                    .font(.subheadline)
                    .foregroundStyle(isEnabled ? .primary : .secondary)

                Spacer()

                Button("Open Safari Settings") {
                    SFSafariApplication.showPreferencesForExtension(
                        withIdentifier: safariExtensionBundleIdentifier
                    )
                }
                .controlSize(.small)
            }

            if !isEnabled {
                Text("Enable the Tether extension in Safari > Settings > Extensions to block websites during focus sessions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let extensionErrorMessage {
                Text(extensionErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            await refreshExtensionState()
        }
    }

    private nonisolated func fetchExtensionState(
        bundleId: String
    ) async -> (SFSafariExtensionState?, (any Error)?) {
        await withCheckedContinuation { continuation in
            // SFSafariExtensionManager's callback is annotated NS_SWIFT_UI_ACTOR (@MainActor)
            // in the SDK header, but Apple's XPC implementation invokes it on a background
            // thread. Swift inserts _swift_task_checkIsolatedSwift at the start of any
            // @MainActor closure body, so the assertion fires before any user code runs.
            //
            // Workaround: create a @Sendable closure (no isolation check injected), then
            // unsafeBitCast to the @MainActor type the parameter expects. Both types have
            // identical ABI (fn ptr + context ptr), and no conversion thunk is emitted at
            // the call site since the types already match after the cast.
            typealias MainActorCompletion = @MainActor (SFSafariExtensionState?, (any Error)?) -> Void
            let nonisolatedCompletion: @Sendable (SFSafariExtensionState?, (any Error)?) -> Void = { state, error in
                continuation.resume(returning: (state, error))
            }
            SFSafariExtensionManager.getStateOfSafariExtension(
                withIdentifier: bundleId,
                completionHandler: unsafeBitCast(nonisolatedCompletion, to: MainActorCompletion.self)
            )
        }
    }

    private func refreshExtensionState() async {
        isChecking = true
        extensionErrorMessage = nil

        let (state, error) = await fetchExtensionState(bundleId: safariExtensionBundleIdentifier)
        // Back on @MainActor after await — safe to mutate @State vars
        isChecking = false
        if let error {
            isEnabled = false
            extensionErrorMessage = "Unable to check Safari extension status: \(error.localizedDescription)"
        } else if let state {
            isEnabled = state.isEnabled
            extensionErrorMessage = nil
        } else {
            isEnabled = false
            extensionErrorMessage = "Safari extension state is unavailable. Open Safari Settings to verify it is enabled."
        }
    }
}

// MARK: - Privacy Settings

struct PrivacySettingsView: View {
    @State private var visibility: VisibilityLevel = .privateOnly
    @State private var isSaving = false
    @State private var isLoading = true

    enum VisibilityLevel: String, CaseIterable {
        case privateOnly = "private"
        case friends = "friends"
        case group = "group"

        var label: String {
            switch self {
            case .privateOnly: "Private"
            case .friends: "All Friends"
            case .group: "Group Only"
            }
        }

        var description: String {
            switch self {
            case .privateOnly: "Your focus stats are hidden from everyone"
            case .friends: "All your friends can see your stats and activity"
            case .group: "Only members of your groups can see your stats"
            }
        }

        var icon: String {
            switch self {
            case .privateOnly: "lock.fill"
            case .friends: "person.2.fill"
            case .group: "person.3.fill"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Privacy", systemImage: "hand.raised.fill")
                .font(.headline)

            Text("Control who can see your focus activity and stats on leaderboards.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if isLoading {
                ProgressView()
                    .controlSize(.small)
            } else {
                ForEach(VisibilityLevel.allCases, id: \.self) { level in
                    HStack(spacing: 12) {
                        Image(systemName: level == visibility ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(level == visibility ? Color.accentColor : .secondary)
                            .font(.title3)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Image(systemName: level.icon)
                                    .font(.caption)
                                Text(level.label)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                            Text(level.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !isSaving else { return }
                        withAnimation {
                            visibility = level
                        }
                        Task { await saveVisibility(level) }
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(level.label): \(level.description)")
                    .accessibilityValue(level == visibility ? "Selected" : "")
                    .accessibilityAddTraits(level == visibility ? .isSelected : [])
                    .accessibilityAddTraits(.isButton)
                }

                if visibility != .privateOnly {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.caption)
                        Text("Others will see your focused time, session count, and streak on shared leaderboards.")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                }
            }
        }
        .task {
            await loadVisibility()
        }
    }

    private func loadVisibility() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let settings: PrivacyUserSettings = try await APIClient.shared.request(.authMe)
            if let vis = settings.settingsJson?["visibility"] {
                visibility = VisibilityLevel(rawValue: vis) ?? .privateOnly
            }
        } catch {
            // Default to private if we can't load
            visibility = .privateOnly
        }
    }

    private func saveVisibility(_ level: VisibilityLevel) async {
        isSaving = true
        defer { isSaving = false }
        do {
            let body = ["settings_json": ["visibility": level.rawValue]]
            try await APIClient.shared.requestVoid(
                .updateSettings, method: "PATCH", body: body
            )
        } catch {
            TetherLogger.general.error("Failed to save visibility: \(error.localizedDescription)")
        }
    }
}

/// Lightweight decode of the /auth/me response for reading user settings.
/// Note: No CodingKeys needed -- APIClient's decoder uses .convertFromSnakeCase.
private struct PrivacyUserSettings: Codable, Sendable {
    let id: UUID
    let email: String
    let settingsJson: [String: String]?
}

#Preview {
    SettingsView()
}
