import Speech
import AVFoundation
import os

/// On-device speech recognition manager for voice-to-text task planning.
/// Uses `SFSpeechRecognizer` with on-device recognition to transcribe
/// microphone input in real time.
///
/// Must remain on `@MainActor` since Speech and AVFoundation APIs
/// interact with system services that require main thread access.
@MainActor
@Observable
public final class SpeechRecognitionManager {

    // MARK: - Public State

    /// Whether the microphone is actively recording.
    public private(set) var isRecording = false

    /// The current transcript from the speech recognizer.
    /// Updated in real time as partial results arrive.
    public private(set) var transcript = ""

    /// Human-readable error message, if any.
    public private(set) var error: String?

    /// Whether speech recognition is available on this device.
    public var isAvailable: Bool {
        guard let recognizer else { return false }
        return recognizer.isAvailable && authorizationStatus == .authorized
    }

    // MARK: - Private

    private let recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private let logger = TetherLogger.speech

    private var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined

    // MARK: - Init

    public init(locale: Locale = .current) {
        self.recognizer = SFSpeechRecognizer(locale: locale)
        self.authorizationStatus = SFSpeechRecognizer.authorizationStatus()
    }

    // MARK: - Authorization

    /// Requests authorization for speech recognition and microphone access.
    /// Call this before the first recording attempt.
    public func requestAuthorization() async {
        // Request speech recognition permission.
        // NOTE: SFSpeechRecognizer.requestAuthorization's completion handler is
        // annotated @MainActor in SDK headers but Apple's XPC invokes it on a
        // background thread. Swift 6.2 inserts a runtime isolation check that
        // triggers _dispatch_assert_queue_fail / BRK #0x1. Work around by
        // passing a nonisolated closure via unsafeBitCast (same pattern as
        // SafariExtensionStatusView).
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            typealias MainActorCompletion = @MainActor (SFSpeechRecognizerAuthorizationStatus) -> Void
            let nonisolatedCompletion: @Sendable (SFSpeechRecognizerAuthorizationStatus) -> Void = { [weak self] status in
                Task { @MainActor in
                    guard let self else { return }
                    self.authorizationStatus = status
                    switch status {
                    case .authorized:
                        self.logger.info("Speech recognition authorized")
                        self.error = nil
                    case .denied:
                        self.logger.notice("Speech recognition denied by user")
                        self.error = "Speech recognition access denied. Enable it in System Settings > Privacy & Security."
                    case .restricted:
                        self.logger.notice("Speech recognition restricted on this device")
                        self.error = "Speech recognition is restricted on this device."
                    case .notDetermined:
                        self.logger.notice("Speech recognition authorization not determined")
                        self.error = nil
                    @unknown default:
                        self.error = "Unknown speech recognition authorization status."
                    }
                }
                continuation.resume()
            }
            SFSpeechRecognizer.requestAuthorization(
                unsafeBitCast(nonisolatedCompletion, to: MainActorCompletion.self)
            )
        }
    }

    // MARK: - Recording

    /// Starts recording from the microphone and transcribing speech.
    /// The `transcript` property updates in real time as partial results arrive.
    public func startRecording() {
        guard let recognizer, recognizer.isAvailable else {
            error = "Speech recognition is not available on this device."
            logger.error("Speech recognizer unavailable")
            return
        }

        guard authorizationStatus == .authorized else {
            error = "Speech recognition is not authorized."
            logger.error("Speech recognition not authorized, status: \(String(describing: self.authorizationStatus))")
            Task { await requestAuthorization() }
            return
        }

        // Cancel any in-progress task
        stopRecording()

        // Reset state
        transcript = ""
        error = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        self.recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // Capture request locally — the audio tap callback runs on a real-time
        // audio thread and must not access actor-isolated properties. append()
        // is thread-safe per Apple docs.
        let capturedRequest = request
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            capturedRequest.append(buffer)
        }

        // NOTE: recognitionTask(with:resultHandler:)'s handler is annotated
        // @MainActor in SDK headers but Apple's XPC invokes it on a background
        // thread — same issue as requestAuthorization above.
        typealias MainActorResultHandler = @MainActor (SFSpeechRecognitionResult?, (any Error)?) -> Void
        let nonisolatedHandler: @Sendable (SFSpeechRecognitionResult?, (any Error)?) -> Void = { [weak self] result, taskError in
            // Extract Sendable values before crossing isolation boundary —
            // SFSpeechRecognitionResult is not Sendable.
            let transcriptText = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let errorDesc = taskError?.localizedDescription
            let nsError = taskError.map { $0 as NSError }

            Task { @MainActor in
                guard let self else { return }

                if let transcriptText {
                    self.transcript = transcriptText

                    if isFinal {
                        self.logger.info("Final transcript received: \(transcriptText.prefix(80))...")
                        self.cleanupAudioSession()
                        self.isRecording = false
                    }
                }

                if let errorDesc {
                    // Don't treat cancellation as an error
                    if nsError?.domain != "kAFAssistantErrorDomain" || nsError?.code != 216 {
                        self.error = errorDesc
                        self.logger.error("Recognition error: \(errorDesc)")
                    }
                    self.cleanupAudioSession()
                    self.isRecording = false
                }
            }
        }
        recognitionTask = recognizer.recognitionTask(
            with: request,
            resultHandler: unsafeBitCast(nonisolatedHandler, to: MainActorResultHandler.self)
        )

        do {
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
            logger.info("Recording started")
        } catch {
            self.error = "Failed to start audio engine: \(error.localizedDescription)"
            logger.error("Audio engine start failed: \(error.localizedDescription)")
            cleanupAudioSession()
            isRecording = false
        }
    }

    /// Stops recording and finalizes the transcript.
    public func stopRecording() {
        guard isRecording || audioEngine.isRunning else { return }

        logger.info("Stopping recording")
        recognitionRequest?.endAudio()
        cleanupAudioSession()
        isRecording = false
    }

    // MARK: - Cleanup

    private func cleanupAudioSession() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
    }
}
