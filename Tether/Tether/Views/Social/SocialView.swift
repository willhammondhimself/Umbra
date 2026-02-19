import SwiftUI
import TetherKit

struct SocialView: View {
    @State private var selectedTab: SocialTab = .friends

    enum SocialTab: String, CaseIterable {
        case friends = "Friends"
        case groups = "Groups"
        case activity = "Activity"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with tab picker
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Social")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("Stay accountable with friends")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                Picker("", selection: $selectedTab) {
                    ForEach(SocialTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 280)
                .accessibilityLabel("Social section")
                .accessibilityValue(selectedTab.rawValue)
            }
            .padding()

            Divider()

            // Content
            switch selectedTab {
            case .friends:
                FriendsListView()
            case .groups:
                GroupsContainerView()
            case .activity:
                ActivityFeedView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Activity Feed Models

struct FriendActivity: Identifiable, Codable {
    let id: UUID
    let userId: UUID
    let displayName: String?
    let startTime: Date
    let durationSeconds: Int
    let focusedSeconds: Int
    let reactions: [ReactionItem]

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case displayName = "display_name"
        case startTime = "start_time"
        case durationSeconds = "duration_seconds"
        case focusedSeconds = "focused_seconds"
        case reactions
    }
}

struct ReactionItem: Identifiable, Codable {
    let id: UUID
    let userId: UUID
    let displayName: String?
    let reactionType: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case displayName = "display_name"
        case reactionType = "reaction_type"
    }
}

// MARK: - Activity Feed View

struct ActivityFeedView: View {
    @State private var activities: [FriendActivity] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                Spacer()
                ProgressView("Loading activity...")
                    .frame(maxWidth: .infinity)
                Spacer()
            } else if activities.isEmpty {
                ContentUnavailableView(
                    "No Recent Activity",
                    systemImage: "person.3",
                    description: Text("Your friends' completed sessions from the last 7 days will appear here.")
                )
            } else {
                List(activities) { activity in
                    ActivityRow(activity: activity, onReact: { reactionType in
                        Task { await sendReaction(sessionId: activity.id, type: reactionType) }
                    })
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }

            // Inline error banner
            if let error = errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                    Text(error)
                        .font(.caption)
                    Spacer()
                    Button {
                        withAnimation(.tetherQuick) { errorMessage = nil }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Dismiss error")
                }
                .foregroundStyle(Color.tetherDistracted)
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
        }
        .task {
            await loadActivity()
        }
    }

    private func loadActivity() async {
        isLoading = true
        defer { isLoading = false }
        do {
            activities = try await APIClient.shared.request(.socialActivity)
        } catch {
            withAnimation(.tetherQuick) {
                errorMessage = "Failed to load activity feed"
            }
        }
    }

    private func sendReaction(sessionId: UUID, type: String) async {
        do {
            let body = ["reaction_type": type]
            let _: ReactionResponse = try await APIClient.shared.request(
                .reactToSession(sessionId), method: "POST", body: body
            )
            // Refresh to show updated reactions
            await loadActivity()
        } catch {
            withAnimation(.tetherQuick) {
                errorMessage = "Failed to send reaction"
            }
        }
    }
}

// MARK: - Reaction Response (local decode type)

private struct ReactionResponse: Codable {
    let id: UUID
    let userId: UUID
    let displayName: String?
    let reactionType: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case displayName = "display_name"
        case reactionType = "reaction_type"
        case createdAt = "created_at"
    }
}

// MARK: - Activity Row

struct ActivityRow: View {
    let activity: FriendActivity
    let onReact: (String) -> Void

    private var thumbsUpCount: Int {
        activity.reactions.filter { $0.reactionType == "thumbs_up" }.count
    }

    private var fireCount: Int {
        activity.reactions.filter { $0.reactionType == "fire" }.count
    }

    private var formattedDuration: String {
        let minutes = activity.durationSeconds / 60
        if minutes < 60 {
            return "\(minutes)m"
        }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return remainingMinutes > 0 ? "\(hours)h \(remainingMinutes)m" : "\(hours)h"
    }

    private var focusPercentage: Int {
        guard activity.durationSeconds > 0 else { return 0 }
        return Int(Double(activity.focusedSeconds) / Double(activity.durationSeconds) * 100)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Friend name and time
            HStack {
                Text(activity.displayName ?? "Friend")
                    .font(.headline)
                Spacer()
                Text(activity.startTime, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Session stats
            HStack(spacing: 16) {
                Label(formattedDuration, systemImage: "clock")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Label("\(focusPercentage)% focused", systemImage: "eye")
                    .font(.subheadline)
                    .foregroundStyle(Color.tetherFocused)
            }

            // Reaction buttons
            HStack(spacing: 12) {
                Button {
                    onReact("thumbs_up")
                } label: {
                    HStack(spacing: 4) {
                        Text("\u{1F44D}")
                        if thumbsUpCount > 0 {
                            Text("\(thumbsUpCount)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .glassPill()
                }
                .buttonStyle(.tetherPressable)
                .accessibilityLabel("Thumbs up")
                .accessibilityValue(thumbsUpCount > 0 ? "\(thumbsUpCount)" : "No reactions")

                Button {
                    onReact("fire")
                } label: {
                    HStack(spacing: 4) {
                        Text("\u{1F525}")
                        if fireCount > 0 {
                            Text("\(fireCount)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .glassPill()
                }
                .buttonStyle(.tetherPressable)
                .accessibilityLabel("Fire reaction")
                .accessibilityValue(fireCount > 0 ? "\(fireCount)" : "No reactions")

                Spacer()
            }
        }
        .padding(.vertical, 6)
    }
}
