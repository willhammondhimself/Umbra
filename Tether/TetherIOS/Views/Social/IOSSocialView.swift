import SwiftUI
import TetherKit

struct IOSSocialView: View {
    @State private var selectedSection: SocialSection = .friends

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $selectedSection) {
                Text("Friends").tag(SocialSection.friends)
                Text("Groups").tag(SocialSection.groups)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            switch selectedSection {
            case .friends:
                IOSFriendsListView()
            case .groups:
                IOSGroupsView()
            }
        }
    }

    enum SocialSection {
        case friends, groups
    }
}

// MARK: - Friends List

struct IOSFriendsListView: View {
    @State private var friends: [FriendItem] = []
    @State private var inviteEmail = ""
    @State private var isInviting = false
    @State private var isLoading = true
    @State private var showEncourageSheet = false
    @State private var selectedFriend: FriendItem?
    @State private var errorMessage: String?

    private var pendingInvites: [FriendItem] {
        friends.filter { $0.status == "pending" }
    }

    private var acceptedFriends: [FriendItem] {
        friends.filter { $0.status == "accepted" }
    }

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
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                        Text(error)
                            .font(.caption)
                        Spacer()
                        Button {
                            withAnimation { errorMessage = nil }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption2)
                        }
                        .buttonStyle(.borderless)
                    }
                    .foregroundStyle(Color.tetherDistracted)
                }
            }

            if isLoading {
                HStack {
                    Spacer()
                    ProgressView("Loading friends...")
                    Spacer()
                }
                .listRowBackground(Color.clear)
            } else if friends.isEmpty {
                ContentUnavailableView(
                    "No Friends Yet",
                    systemImage: "person.2",
                    description: Text("Invite friends to hold each other accountable.")
                )
            } else {
                if !pendingInvites.isEmpty {
                    Section("Pending Invites") {
                        ForEach(pendingInvites) { friend in
                            friendRow(friend)
                        }
                    }
                }

                if !acceptedFriends.isEmpty {
                    Section("Friends") {
                        ForEach(acceptedFriends) { friend in
                            friendRow(friend)
                        }
                    }
                }
            }
        }
        .refreshable {
            await loadFriends()
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

    @ViewBuilder
    private func friendRow(_ friend: FriendItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(friend.displayName ?? friend.email)
                    .font(.body)
                if friend.status == "pending" {
                    Text("Invite sent")
                        .font(.caption)
                        .foregroundStyle(Color.tetherPaused)
                } else {
                    Text("Since \(friend.since, format: .dateTime.month().year())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if friend.status == "pending" {
                Button("Accept") {
                    Task { await acceptInvite(friend) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(Color.tetherFocused)
            } else if friend.status == "accepted" {
                Button {
                    selectedFriend = friend
                    showEncourageSheet = true
                } label: {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(Color.tetherDistracted)
                }

                Button {
                    Task { await sendPing(to: friend) }
                } label: {
                    Image(systemName: "bell.fill")
                        .foregroundStyle(Color.tetherPaused)
                }
            }
        }
    }

    // MARK: - Actions

    private func loadFriends() async {
        isLoading = true
        defer { isLoading = false }
        do {
            friends = try await APIClient.shared.request(.friends)
        } catch {
            errorMessage = "Failed to load friends"
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

    private func acceptInvite(_ friend: FriendItem) async {
        do {
            try await APIClient.shared.requestVoid(
                .friendAccept(friend.id), method: "POST"
            )
            await loadFriends()
        } catch {
            errorMessage = "Failed to accept invite"
        }
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
