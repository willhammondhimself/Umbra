import SwiftUI

struct FriendsListView: View {
    @State private var friends: [FriendItem] = []
    @State private var inviteEmail = ""
    @State private var isInviting = false
    @State private var showEncourageSheet = false
    @State private var selectedFriend: FriendItem?
    @State private var errorMessage: String?

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

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }

            if friends.isEmpty {
                ContentUnavailableView(
                    "No Friends Yet",
                    systemImage: "person.2",
                    description: Text("Invite friends to hold each other accountable.")
                )
            } else {
                List(friends) { friend in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(friend.displayName ?? friend.email)
                                .font(.headline)
                            if friend.status == "pending" {
                                Text("Pending")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }

                        Spacer()

                        if friend.status == "accepted" {
                            Button {
                                selectedFriend = friend
                                showEncourageSheet = true
                            } label: {
                                Image(systemName: "heart.fill")
                            }
                            .buttonStyle(.borderless)

                            Button {
                                Task { await sendPing(to: friend) }
                            } label: {
                                Image(systemName: "bell.fill")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .padding(.vertical, 4)
                }
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

    private func loadFriends() async {
        do {
            friends = try await APIClient.shared.request(.friends)
        } catch {
            print("Failed to load friends: \(error)")
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

// MARK: - Supporting Types

struct FriendItem: Identifiable, Codable {
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

private struct InviteResponse: Codable {
    let id: UUID
    let status: String
}
