import Foundation
import Speech
import AVFoundation
import Observation

/// Service de dictée vocale en direct basé sur `SFSpeechRecognizer` (`fr-FR`) et `AVAudioEngine`.
/// Premier appui : démarre l'écoute et transcrit en direct. Second appui : arrête l'écoute pour relecture.
@Observable
final class SpeechRecognizer: @unchecked Sendable {
    private(set) var isRecording = false
    var permissionDeniedMessage: String?
    var errorMessage: String?

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var activeSessionID: UUID?

    init() {}

    @MainActor
    func toggleRecording(
        currentText: String,
        onTranscript: @escaping @MainActor (String) -> Void
    ) async {
        if isRecording {
            stopRecording()
            return
        }
        await startRecording(currentText: currentText, onTranscript: onTranscript)
    }

    @MainActor
    func startRecording(
        currentText: String,
        onTranscript: @escaping @MainActor (String) -> Void
    ) async {
        permissionDeniedMessage = nil
        errorMessage = nil

        let speechStatus = await Self.requestSpeechAuthorization()
        guard speechStatus == .authorized else {
            permissionDeniedMessage = "L'accès à la reconnaissance vocale est désactivé. Autorise Monika dans les Réglages iOS pour dicter tes messages."
            return
        }

        let micAllowed = await AVAudioApplication.requestRecordPermission()
        guard micAllowed else {
            permissionDeniedMessage = "L'accès au microphone est désactivé. Autorise Monika dans les Réglages iOS pour dicter tes messages."
            return
        }

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "fr-FR")),
              recognizer.isAvailable
        else {
            errorMessage = "La reconnaissance vocale en français est temporairement indisponible."
            return
        }

        stopRecording()

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.addsPunctuation = true
            recognitionRequest = request

            let engine = AVAudioEngine()
            let inputNode = engine.inputNode
            inputNode.removeTap(onBus: 0)
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
                errorMessage = "Aucune entrée audio disponible sur cet appareil."
                cleanupAudioSession()
                return
            }

            Self.installAudioTap(on: inputNode, format: recordingFormat, request: request)

            engine.prepare()
            try engine.start()
            audioEngine = engine

            let sessionID = UUID()
            activeSessionID = sessionID
            isRecording = true

            let prefix = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                let transcript = result?.bestTranscription.formattedString
                let isFinal = result?.isFinal ?? false
                let hasError = (error != nil)

                Task { @MainActor [weak self] in
                    guard let self, self.activeSessionID == sessionID, self.isRecording else { return }

                    if let transcript, !transcript.isEmpty {
                        let updated = prefix.isEmpty ? transcript : "\(prefix) \(transcript)"
                        onTranscript(updated)
                    }

                    if isFinal || hasError {
                        self.stopRecording()
                    }
                }
            }
        } catch {
            stopRecording()
            errorMessage = "Impossible de démarrer l'enregistrement vocal."
        }
    }

    func stopRecording() {
        activeSessionID = nil
        let wasRecording = isRecording
        isRecording = false

        if let engine = audioEngine {
            if engine.isRunning {
                engine.stop()
            }
            engine.inputNode.removeTap(onBus: 0)
            audioEngine = nil
        }

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        recognitionTask?.cancel()
        recognitionTask = nil

        if wasRecording {
            cleanupAudioSession()
        }
    }

    // MARK: - Helpers non-isolés (thread audio temps réel)

    private func cleanupAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private nonisolated static func installAudioTap(
        on inputNode: AVAudioInputNode,
        format: AVAudioFormat,
        request: SFSpeechAudioBufferRecognitionRequest
    ) {
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
    }

    private nonisolated static func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        let current = SFSpeechRecognizer.authorizationStatus()
        guard current == .notDetermined else { return current }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
}
