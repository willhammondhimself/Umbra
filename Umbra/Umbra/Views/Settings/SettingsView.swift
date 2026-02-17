import SwiftUI

struct SettingsView: View {
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Settings")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("Configure Umbra to work for you")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()

            Divider()

            HSplitView {
                // Blocklist editor
                BlocklistEditorView()
                    .frame(minWidth: 300)

                // Account settings
                AccountSettingsView()
                    .frame(minWidth: 300)
            }
        }
    }
}

#Preview {
    SettingsView()
}
