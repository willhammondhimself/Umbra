import Foundation
import Speech
import AVFoundation
import os

@Observable
final class VoiceInputManager {
    private(set) var isRecording = false
    private(set) var transcript = ""
    private(set) var error: String?

    private var audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

    // MARK: - Public Interface

    @MainActor
    func startRecording() {
        // Check authorization synchronously on macOS
        let status = SFSpeechRecognizer.authorizationStatus()
        guard status == .authorized else {
            // If not authorized, request authorization
            if status == .notDetermined {
                SFSpeechRecognizer.requestAuthorization { _ in }
                error = "Please enable speech recognition in System Preferences"
            } else {
                error = "Speech recognition not authorized"
            }
            return
        }

        guard speechRecognizer?.isAvailable == true else {
            error = "Speech recognition not available"
            return
        }

        // Cancel any existing recognition task
        if let recognitionTask = recognitionTask {
            recognitionTask.cancel()
            self.recognitionTask = nil
        }

        error = nil
        transcript = ""
        isRecording = true

        do {
            try startAudioEngine()
            let request = SFSpeechAudioBufferRecognitionRequest()
            self.recognitionRequest = request
            request.shouldReportPartialResults = true

            recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
                guard let self = self else { return }

                if let error = error {
                    Task { @MainActor in
                        self.error = "Recognition error: \(error.localizedDescription)"
                        self.isRecording = false
                    }
                    return
                }

                if let result = result {
                    Task { @MainActor in
                        self.transcript = result.bestTranscription.formattedString
                        if result.isFinal {
                            self.stopRecording()
                        }
                    }
                }
            }
        } catch {
            self.error = "Failed to start recording: \(error.localizedDescription)"
            isRecording = false
        }
    }

    @MainActor
    func stopRecording() {
        isRecording = false
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
    }

    // MARK: - Private Helpers

    private func startAudioEngine() throws {
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0) ?? AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
    }
}
