import AVFoundation
import Speech

/// Korean speech-to-text for the coach composer. Recognition runs on the device when the
/// recognizer supports it; audio is never stored.
@MainActor
final class SpeechInput: ObservableObject {
    @Published private(set) var isRecording = false
    @Published var transcript = ""
    @Published private(set) var error: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ko-KR"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    /// Called with the final text when recording stops.
    var onFinish: (String) -> Void = { _ in }

    var isOnDevice: Bool { recognizer?.supportsOnDeviceRecognition ?? false }

    func toggle() {
        if isRecording { stop() } else { Task { await start() } }
    }

    func start() async {
        error = nil
        guard await requestPermissions() else {
            error = "설정 앱에서 마이크와 음성 인식을 허용해 주세요."
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            error = "지금은 음성 인식을 사용할 수 없어요."
            return
        }
        transcript = ""
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        self.request = request

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let input = engine.inputNode
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
                request.append(buffer)
            }
            engine.prepare()
            try engine.start()
        } catch {
            self.error = "마이크를 시작하지 못했어요."
            cleanUp()
            return
        }

        isRecording = true
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result { self.transcript = result.bestTranscription.formattedString }
                if error != nil || result?.isFinal == true, self.isRecording { self.stop() }
            }
        }
    }

    func stop() {
        guard isRecording else { return }
        isRecording = false
        request?.endAudio()
        cleanUp()
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { onFinish(text) }
    }

    private func cleanUp() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        task?.cancel()
        task = nil
        request = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func requestPermissions() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        guard speech else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }
}
