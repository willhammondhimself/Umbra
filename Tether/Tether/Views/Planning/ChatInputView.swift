import SwiftUI
import TetherKit

struct ChatInputView: View {
    @Binding var inputText: String
    var onSubmit: (String) -> Void

    @FocusState private var isFocused: Bool
    @State private var speechManager = SpeechRecognitionManager()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

            // Microphone button
            Button(action: toggleRecording) {
                ZStack {
                    if speechManager.isRecording && !reduceMotion {
                        // Pulsing red circle indicator behind mic icon
                        Circle()
                            .fill(Color.red.opacity(0.2))
                            .frame(width: 32, height: 32)
                            .phaseAnimator([false, true]) { content, phase in
                                content
                                    .scaleEffect(phase ? 1.3 : 1.0)
                                    .opacity(phase ? 0.3 : 0.6)
                            } animation: { _ in
                                .easeInOut(duration: 0.8)
                            }
                    } else if speechManager.isRecording {
                        // Static indicator for reduced motion
                        Circle()
                            .fill(Color.red.opacity(0.3))
                            .frame(width: 32, height: 32)
                    }

                    Image(systemName: "mic.fill")
                        .font(.title2)
                        .foregroundStyle(speechManager.isRecording ? Color.red : Color.secondary)
                }
            }
            .buttonStyle(.plain)
            .disabled(!speechManager.isAvailable && !speechManager.isRecording)
            .help(speechManager.isRecording ? "Stop dictation" : "Start dictation")
            .accessibilityLabel(speechManager.isRecording ? "Stop dictation" : "Start dictation")
            .accessibilityValue(speechManager.isRecording ? "Recording" : "Not recording")

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
            .accessibilityLabel("Parse tasks")
        }
        .padding()
        .onAppear {
            isFocused = true
            Task { await speechManager.requestAuthorization() }
        }
        .onChange(of: speechManager.isRecording) { wasRecording, isNowRecording in
            // When recording stops, append transcript to input
            if wasRecording && !isNowRecording {
                let trimmed = speechManager.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }

                if inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    inputText = trimmed
                } else {
                    inputText += " " + trimmed
                }
            }
        }
    }

    private func submit() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        onSubmit(text)
        inputText = ""
    }

    private func toggleRecording() {
        if speechManager.isRecording {
            speechManager.stopRecording()
        } else {
            speechManager.startRecording()
        }
    }
}
