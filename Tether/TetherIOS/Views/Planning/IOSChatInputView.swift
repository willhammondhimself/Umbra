import SwiftUI
import TetherKit

struct IOSChatInputView: View {
    @Binding var inputText: String
    var onSubmit: (String) -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Describe your tasks...", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .focused($isFocused)
                .onSubmit {
                    submit()
                }
                .padding(10)
                .glassCard(cornerRadius: TetherRadius.button)

            Button(action: submit) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(inputText.trimmingCharacters(in: .whitespaces).isEmpty ? Color.secondary : Color.accentColor)
            }
            .buttonStyle(.tetherPressable)
            .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty)
            .accessibilityLabel("Parse tasks")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func submit() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        onSubmit(text)
        inputText = ""
    }
}
