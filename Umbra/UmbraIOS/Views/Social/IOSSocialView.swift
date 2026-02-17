import SwiftUI
import UmbraKit

struct IOSSocialView: View {
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text("Friends").tag(0)
                Text("Groups").tag(1)
            }
            .pickerStyle(.segmented)
            .padding()

            if selectedTab == 0 {
                IOSFriendsListView()
            } else {
                IOSGroupView()
            }
        }
    }
}

// MARK: - Friends List

struct IOSFriendsListView: View {
    @State private var friends: [FriendItem] = []
    @State private var inviteEmail = ""
    @State private var isInviting = false
    @State private var showEncourageSheet = false
    @State private var selectedFriend: FriendItem?
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("Friend's email", text: $inviteEmail)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)

                    Button("Invite") {
                        Task { await sendInvite() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(inviteEmail.isEmpty || isInviting)
                }

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            if friends.isEmpty {
                ContentUnavailableView(
                    "No Friends Yet",
                    systemImage: "person.2",
                    description: Text("Invite friends to hold each other accountable.")
                )
            } else {
                ForEach(friends) { friend in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(friend.displayName ?? friend.email)
                                .font(.body)
                            if friend.status == "pending" {
                                Text("Pending")
                                    .font(.caption)
                                    .foregroundStyle(Color.umbraPaused)
                            }
                        }

                        Spacer()

                        if friend.status == "accepted" {
                            Button {
                                selectedFriend = friend
                                showEncourageSheet = true
                            } label: {
                                Image(systemName: "heart.fill")
                                    .foregroundStyle(Color.umbraDistracted)
                            }

                            Button {
                                Task { await sendPing(to: friend) }
                            } label: {
                                Image(systemName: "bell.fill")
                                    .foregroundStyle(Color.umbraPaused)
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showEncourageSheet) {
            if let friend = selectedFriend {
                IOSEncourageView(friend: friend)
            }
        }
        .task {
            await loadFriends()
        }
    }

    private func loadFriends() async {
        do {
            friends = try await APIClient.shared.request(.friends)
        } catch {
            // Non-critical
        }
    }

    private func sendInvite() async {
        isInviting = true
        errorMessage = nil
        do {
            let body = ["email": inviteEmail]
            let _: InviteResponse = try await APIClient.shared.request(
                .friendInvite, method: "POST", body: body
            )
            inviteEmail = ""
            await loadFriends()
        } catch {
            errorMessage = "Failed to send invite"
        }
        isInviting = false
    }

    private func sendPing(to friend: FriendItem) async {
        do {
            let body = ["to_user_id": friend.userId.uuidString]
            try await APIClient.shared.requestVoid(.socialPing, method: "POST", body: body)
        } catch {
            errorMessage = "Failed to send ping"
        }
    }
}

private struct InviteResponse: Codable {
    let id: UUID
    let status: String
}

// MARK: - Encourage View

struct IOSEncourageView: View {
    let friend: FriendItem

    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
    @State private var isSending = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Send encouragement to \(friend.displayName ?? friend.email)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                TextEditor(text: $message)
                    .frame(height: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.quaternary)
                    )

                Spacer()
            }
            .padding()
            .navigationTitle("Encourage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        Task { await send() }
                    }
                    .disabled(message.isEmpty || isSending)
                }
            }
        }
    }

    private func send() async {
        isSending = true
        do {
            let body: [String: String] = [
                "to_user_id": friend.userId.uuidString,
                "message": message,
            ]
            try await APIClient.shared.requestVoid(.socialEncourage, method: "POST", body: body)
            dismiss()
        } catch {
            // Non-critical
        }
        isSending = false
    }
}

// MARK: - Group Views

struct IOSGroupView: View {
    @State private var groups: [GroupItem] = []

    var body: some View {
        if groups.isEmpty {
            ContentUnavailableView(
                "No Groups",
                systemImage: "person.3",
                description: Text("Groups let you compete on leaderboards with friends.")
            )
            .task { await loadGroups() }
        } else {
            List(groups) { group in
                NavigationLink {
                    IOSLeaderboardView(groupId: group.id, groupName: group.name)
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(group.name)
                                .font(.body)
                            Text("\(group.memberCount) members")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "trophy")
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .task { await loadGroups() }
        }
    }

    private func loadGroups() async {
        do {
            groups = try await APIClient.shared.request(.groups)
        } catch {
            // Non-critical
        }
    }
}

// MARK: - Leaderboard

struct IOSLeaderboardView: View {
    let groupId: UUID
    let groupName: String

    @State private var entries: [LeaderboardEntryItem] = []

    var body: some View {
        List(entries) { entry in
            HStack {
                ZStack {
                    Circle()
                        .fill(entry.rank <= 3 ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.1))
                        .frame(width: 32, height: 32)
                    Text("\(entry.rank)")
                        .font(.caption.bold())
                        .foregroundStyle(entry.rank <= 3 ? Color.accentColor : .secondary)
                }

                Text(entry.displayName ?? "Anonymous")

                Spacer()

                VStack(alignment: .trailing) {
                    Text(formatTime(entry.focusedSeconds))
                        .font(.headline)
                    Text("\(entry.sessionCount) sessions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(groupName)
        .task { await loadLeaderboard() }
    }

    private func formatTime(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    private func loadLeaderboard() async {
        do {
            entries = try await APIClient.shared.request(.groupLeaderboard(groupId))
        } catch {
            // Non-critical
        }
    }
}

// MARK: - Shared Model Types

struct FriendItem: Identifiable, Codable, Sendable {
    let id: UUID
    let userId: UUID
    let displayName: String?
    let email: String
    let status: String
    let since: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case displayName = "display_name"
        case email, status, since
    }
}

struct GroupItem: Identifiable, Codable, Sendable {
    let id: UUID
    let name: String
    let createdBy: UUID
    let createdAt: Date
    let memberCount: Int

    enum CodingKeys: String, CodingKey {
        case id, name
        case createdBy = "created_by"
        case createdAt = "created_at"
        case memberCount = "member_count"
    }
}

struct LeaderboardEntryItem: Identifiable, Codable, Sendable {
    var id: UUID { userId }
    let userId: UUID
    let displayName: String?
    let focusedSeconds: Int
    let sessionCount: Int
    let rank: Int

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case displayName = "display_name"
        case focusedSeconds = "focused_seconds"
        case sessionCount = "session_count"
        case rank
    }
}
