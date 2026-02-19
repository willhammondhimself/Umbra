import SwiftUI
import TetherKit

struct GroupsContainerView: View {
    @State private var groups: [GroupItem] = []
    @State private var isLoading = true
    @State private var showCreateSheet = false
    @State private var newGroupName = ""
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Create group bar
            HStack {
                Text("Your Groups")
                    .font(.headline)
                Spacer()
                Button {
                    showCreateSheet = true
                } label: {
                    Label("Create Group", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .buttonStyle(.tetherPressable)
                .controlSize(.small)
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
                    .accessibilityLabel("Dismiss error")
                }
                .foregroundStyle(Color.tetherDistracted)
                .padding(.horizontal)
                .padding(.bottom, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            if isLoading {
                Spacer()
                ProgressView("Loading groups...")
                    .frame(maxWidth: .infinity)
                Spacer()
            } else if groups.isEmpty {
                ContentUnavailableView(
                    "No Groups Yet",
                    systemImage: "person.3",
                    description: Text("Create a group to compete on leaderboards with friends.")
                )
            } else {
                List(groups) { group in
                    NavigationLink {
                        LeaderboardView(groupId: group.id, groupName: group.name)
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(group.name)
                                    .font(.headline)
                                Text("\(group.memberCount) members")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "trophy")
                                .foregroundStyle(Color.accentColor)
                                .accessibilityHidden(true)
                        }
                    }
                    .accessibilityLabel("\(group.name), \(group.memberCount) members")
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            createGroupSheet
        }
        .task {
            await loadGroups()
        }
    }

    private var createGroupSheet: some View {
        VStack(spacing: 20) {
            Text("Create Group")
                .font(.title2.bold())

            Text("Create an accountability group and invite friends to join.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            TextField("Group name", text: $newGroupName)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 300)

            HStack(spacing: 12) {
                Button("Cancel") {
                    newGroupName = ""
                    showCreateSheet = false
                }
                .buttonStyle(.bordered)

                Button("Create") {
                    Task { await createGroup() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(newGroupName.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
            }
        }
        .padding(30)
        .frame(minWidth: 400)
    }

    // MARK: - Actions

    private func loadGroups() async {
        isLoading = true
        defer { isLoading = false }
        do {
            groups = try await APIClient.shared.request(.groups)
        } catch {
            withAnimation(.tetherQuick) {
                errorMessage = "Failed to load groups"
            }
            TetherLogger.social.error("Failed to load groups: \(error.localizedDescription)")
        }
    }

    private func createGroup() async {
        isCreating = true
        defer { isCreating = false }
        do {
            let body = ["name": newGroupName.trimmingCharacters(in: .whitespaces)]
            let _: GroupItem = try await APIClient.shared.request(
                .createGroup, method: "POST", body: body
            )
            newGroupName = ""
            showCreateSheet = false
            await loadGroups()
        } catch {
            withAnimation(.tetherQuick) {
                errorMessage = "Failed to create group"
            }
            TetherLogger.social.error("Failed to create group: \(error.localizedDescription)")
        }
    }
}
