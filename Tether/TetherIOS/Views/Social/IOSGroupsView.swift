import SwiftUI
import TetherKit

struct IOSGroupsView: View {
    @State private var groups: [GroupItem] = []
    @State private var isLoading = true
    @State private var showCreateSheet = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading groups...")
            } else if groups.isEmpty {
                ContentUnavailableView(
                    "No Groups Yet",
                    systemImage: "person.3",
                    description: Text("Create a group to compete with friends on leaderboards.")
                )
            } else {
                List(groups) { group in
                    NavigationLink {
                        IOSLeaderboardView(groupId: group.id, groupName: group.name)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(group.name)
                                    .font(.headline)
                                Text("\(group.memberCount) member\(group.memberCount == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "trophy")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            IOSCreateGroupSheet { name in
                await createGroup(name: name)
            }
        }
        .refreshable {
            await loadGroups()
        }
        .task {
            await loadGroups()
        }
    }

    private func loadGroups() async {
        isLoading = groups.isEmpty
        defer { isLoading = false }
        do {
            groups = try await APIClient.shared.request(.groups)
        } catch {
            errorMessage = "Failed to load groups"
        }
    }

    private func createGroup(name: String) async {
        do {
            let body = ["name": name]
            let _: GroupItem = try await APIClient.shared.request(.groups, method: "POST", body: body)
            await loadGroups()
        } catch {
            errorMessage = "Failed to create group"
        }
    }
}

// MARK: - Create Group Sheet

struct IOSCreateGroupSheet: View {
    var onCreate: (String) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var groupName = ""
    @State private var isCreating = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Group Name") {
                    TextField("e.g. Study Buddies", text: $groupName)
                        .textInputAutocapitalization(.words)
                }
            }
            .navigationTitle("New Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        isCreating = true
                        Task {
                            await onCreate(groupName)
                            dismiss()
                        }
                    }
                    .disabled(groupName.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
