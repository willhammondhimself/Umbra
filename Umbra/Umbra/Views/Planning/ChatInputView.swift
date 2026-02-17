import SwiftUI

struct ChatInputView: View {
    @Binding var inputText: String
    var onSubmit: (String) -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // Text input
            TextField("Describe your tasks...", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .focused($isFocused)
                .onSubmit {
                    submit()
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.background)
                        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isFocused ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.2), lineWidth: 1)
                )

            // Submit button
            Button(action: submit) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(inputText.trimmingCharacters(in: .whitespaces).isEmpty ? Color.secondary : Color.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty)
            .keyboardShortcut(.return, modifiers: .command)
            .help("Parse tasks (Cmd+Return)")
        }
        .padding()
        .onAppear { isFocused = true }
    }

    private func submit() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        onSubmit(text)
        inputText = ""
    }
}
