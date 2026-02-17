import SwiftUI
import TetherKit

struct FriendsListView: View {
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
        VStack(spacing: 0) {
            // Invite bar
            HStack {
                TextField("Friend's email", text: $inviteEmail)
                    .textFieldStyle(.roundedBorder)

                Button("Invite") {
                    Task { await sendInvite() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(inviteEmail.isEmpty || isInviting)
            }
            .padding()

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
                }
                .foregroundStyle(Color.tetherDistracted)
                .padding(.horizontal)
                .padding(.bottom, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            if isLoading {
                Spacer()
                ProgressView("Loading friends...")
                    .frame(maxWidth: .infinity)
                Spacer()
            } else if friends.isEmpty {
                ContentUnavailableView(
                    "No Friends Yet",
                    systemImage: "person.2",
                    description: Text("Invite friends to hold each other accountable.")
                )
            } else {
                List {
                    // Pending invites section
                    if !pendingInvites.isEmpty {
                        Section("Pending Invites") {
                            ForEach(pendingInvites) { friend in
                                friendRow(friend)
                            }
                        }
                    }

                    // Accepted friends section
                    if !acceptedFriends.isEmpty {
                        Section("Friends") {
                            ForEach(acceptedFriends) { friend in
                                friendRow(friend)
                            }
                        }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .sheet(isPresented: $showEncourageSheet) {
            if let friend = selectedFriend {
                EncourageView(friend: friend)
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
                    .font(.headline)
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
                .buttonStyle(.borderless)
                .help("Send encouragement")

                Button {
                    Task { await sendPing(to: friend) }
                } label: {
                    Image(systemName: "bell.fill")
                        .foregroundStyle(Color.tetherPaused)
                }
                .buttonStyle(.borderless)
                .help("Send accountability ping")
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Actions

    private func loadFriends() async {
        isLoading = true
        defer { isLoading = false }
        do {
            friends = try await APIClient.shared.request(.friends)
        } catch {
            withAnimation(.tetherQuick) {
                errorMessage = "Failed to load friends"
            }
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
            withAnimation(.tetherQuick) {
                errorMessage = "Failed to send invite"
            }
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
            withAnimation(.tetherQuick) {
                errorMessage = "Failed to accept invite"
            }
        }
    }

    private func sendPing(to friend: FriendItem) async {
        do {
            let body = ["to_user_id": friend.userId.uuidString]
            try await APIClient.shared.requestVoid(.socialPing, method: "POST", body: body)
        } catch {
            withAnimation(.tetherQuick) {
                errorMessage = "Failed to send ping"
            }
        }
    }
}
