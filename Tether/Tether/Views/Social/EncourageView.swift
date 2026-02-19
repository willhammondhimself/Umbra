import SwiftUI
import os
import TetherKit

struct EncourageView: View {
    let friend: FriendItem

    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
    @State private var isSending = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Encourage \(friend.displayName ?? friend.email)")
                .font(.title3.bold())

            TextEditor(text: $message)
                .font(.body)
                .frame(height: 100)
                .scrollContentBackground(.hidden)
                .padding(8)
                .glassCard(cornerRadius: TetherRadius.small)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Send") {
                    Task { await send() }
                }
                .buttonStyle(.borderedProminent)
                .buttonStyle(.tetherPressable)
                .disabled(message.isEmpty || isSending)
                .keyboardShortcut(.defaultAction)
                .accessibilityHint("Send encouragement message to \(friend.displayName ?? friend.email)")
            }
        }
        .padding(24)
        .frame(width: 400)
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
            TetherLogger.social.error("Failed to send encouragement: \(error.localizedDescription)")
        }
        isSending = false
    }
}
