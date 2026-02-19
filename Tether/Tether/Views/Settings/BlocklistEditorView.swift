import SwiftUI
import AppKit
import TetherKit

struct BlocklistEditorView: View {
    @State private var blockingManager = BlockingManager.shared
    @State private var showAddSheet = false
    @State private var newBundleId = ""
    @State private var newDomain = ""
    @State private var newDisplayName = ""
    @State private var newBlockMode: BlocklistItem.BlockMode = .softWarn
    @State private var addMode: AddMode = .app

    enum AddMode: String, CaseIterable {
        case app = "App"
        case website = "Website"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Blocklist")
                    .font(.headline)
                Spacer()
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add blocked app or website")
                .accessibilityLabel("Add to blocklist")
            }
            .padding()

            if blockingManager.blocklistItems.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "shield.slash")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text("No blocked apps or websites")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Add Item") { showAddSheet = true }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(blockingManager.blocklistItems) { item in
                        HStack {
                            // Toggle
                            Toggle("", isOn: Binding(
                                get: { item.isEnabled },
                                set: { _ in blockingManager.toggleItem(item) }
                            ))
                            .labelsHidden()
                            .accessibilityLabel("\(item.displayName) blocking")
                            .accessibilityValue(item.isEnabled ? "Enabled" : "Disabled")

                            // Icon
                            Image(systemName: item.isAppBlock ? "app.fill" : "globe")
                                .foregroundStyle(item.isEnabled ? Color.accentColor : Color.secondary)
                                .accessibilityHidden(true)

                            // Name
                            VStack(alignment: .leading) {
                                Text(item.displayName)
                                    .font(.body)
                                Text(item.bundleId ?? item.domain ?? "")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            // Mode badge
                            Text(item.blockMode.label)
                                .font(.caption)
                                .foregroundStyle(modeColor(item.blockMode))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .glassPill()
                                .accessibilityLabel("Block mode: \(item.blockMode.label)")

                            // Delete
                            Button {
                                blockingManager.removeItem(item)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(item.displayName) from blocklist")
                        }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .sheet(isPresented: $showAddSheet) {
            addSheet
        }
        .onAppear {
            blockingManager.loadBlocklist()
        }
    }

    // MARK: - Add Sheet

    private var addSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add to Blocklist")
                    .font(.headline)
                Spacer()
                Button("Cancel") { showAddSheet = false }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            Form {
                Picker("Type", selection: $addMode) {
                    ForEach(AddMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if addMode == .app {
                    TextField("Bundle ID (e.g. com.twitter.twitter)", text: $newBundleId)
                        .textFieldStyle(.roundedBorder)

                    Button("Pick from Running Apps") {
                        pickRunningApp()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    TextField("Domain (e.g. twitter.com)", text: $newDomain)
                        .textFieldStyle(.roundedBorder)
                }

                TextField("Display Name", text: $newDisplayName)
                    .textFieldStyle(.roundedBorder)

                Picker("Block Mode", selection: $newBlockMode) {
                    ForEach(BlocklistItem.BlockMode.allCases, id: \.self) { mode in
                        VStack(alignment: .leading) {
                            Text(mode.label)
                            Text(mode.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(mode)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Add") {
                    addItem()
                }
                .buttonStyle(.borderedProminent)
                .buttonStyle(.tetherPressable)
                .disabled(!canAdd)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 420, height: 380)
    }

    private var canAdd: Bool {
        let hasTarget = addMode == .app ? !newBundleId.isEmpty : !newDomain.isEmpty
        return hasTarget && !newDisplayName.isEmpty
    }

    private func addItem() {
        let item = BlocklistItem(
            bundleId: addMode == .app ? newBundleId : nil,
            domain: addMode == .website ? newDomain : nil,
            displayName: newDisplayName,
            blockMode: newBlockMode
        )
        blockingManager.addItem(item)

        // Reset
        newBundleId = ""
        newDomain = ""
        newDisplayName = ""
        newBlockMode = .softWarn
        showAddSheet = false
    }

    private func pickRunningApp() {
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }

        if let app = apps.first(where: { $0.bundleIdentifier != Bundle.main.bundleIdentifier }) {
            newBundleId = app.bundleIdentifier ?? ""
            newDisplayName = app.localizedName ?? ""
        }
    }

    private func modeColor(_ mode: BlocklistItem.BlockMode) -> Color {
        switch mode {
        case .softWarn: .yellow
        case .hardBlock: .red
        case .timedLock: .orange
        }
    }
}
