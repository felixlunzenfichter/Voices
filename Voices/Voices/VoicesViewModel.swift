import Observation

@Observable @MainActor
final class VoicesViewModel {
    private(set) var isRecording = false {
        didSet { checkMutualExclusion() }
    }
    private(set) var isListening = false {
        didSet { checkMutualExclusion() }
    }
    private(set) var chunks: [Chunk] = []

    private let recordingService: any RecordingService
    private var recordingTask: Task<Void, Never>?

    init(recordingService: any RecordingService = SilentRecordingService()) {
        self.recordingService = recordingService
    }

    func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    func toggleListening() {
        isListening ? stopListening() : startListening()
    }

    private func startRecording() {
        if isListening { stopListening() }
        isRecording = true
        chunks = []
        recordingTask = Task {
            for await chunk in recordingService.chunks() {
                guard !Task.isCancelled else { break }
                chunks.append(chunk)
            }
        }
        log("Recording started")
    }

    private func stopRecording() {
        recordingTask?.cancel()
        recordingTask = nil
        isRecording = false
        log("Recording stopped")
        sendNotification(title: "Recording", body: "Stopped")
    }

    private func startListening() {
        if isRecording { stopRecording() }
        isListening = true
        log("Listening started")
    }

    private func stopListening() {
        isListening = false
        log("Listening stopped")
    }

    private func checkMutualExclusion() {
        if isRecording && isListening {
            logError("INVARIANT: isRecording=\(isRecording) isListening=\(isListening) — both true simultaneously")
        }
    }
}
