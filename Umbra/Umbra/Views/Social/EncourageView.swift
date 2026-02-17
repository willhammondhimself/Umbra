import SwiftUI

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
                .frame(height: 100)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.quaternary)
                )

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Send") {
                    Task { await send() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(message.isEmpty || isSending)
                .keyboardShortcut(.defaultAction)
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
            print("Failed to send encouragement: \(error)")
        }
        isSending = false
    }
}
