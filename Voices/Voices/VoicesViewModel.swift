import Observation

@Observable @MainActor
final class VoicesViewModel {
    private(set) var isRecording = false {
        didSet { checkMutualExclusion() }
    }
    private(set) var isListening = false {
        didSet { checkMutualExclusion() }
    }
    private(set) var audioChunks: [AudioChunk] = []
    private(set) var playbackIndex: Int = -1

    private let recordingService: any RecordingService
    private let playbackService: any PlaybackService
    private var recordingTask: Task<Void, Never>?
    private var playbackTask: Task<Void, Never>?

    init(
        recordingService: any RecordingService = SilentRecordingService(),
        playbackService: any PlaybackService = SilentPlaybackService()
    ) {
        self.recordingService = recordingService
        self.playbackService = playbackService
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
        audioChunks = []
        recordingTask = Task {
            for await audioChunk in recordingService.audioChunks() {
                guard !Task.isCancelled else { break }
                audioChunks.append(audioChunk)
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
        playbackIndex = 0
        playbackTask = Task {
            for await index in playbackService.play(audioChunks) {
                guard !Task.isCancelled else { break }
                playbackIndex = index
            }
            if !Task.isCancelled {
                isListening = false
            }
        }
        log("Listening started")
    }

    private func stopListening() {
        playbackTask?.cancel()
        playbackTask = nil
        isListening = false
        log("Listening stopped")
    }

    private func checkMutualExclusion() {
        if isRecording && isListening {
            logError("INVARIANT: isRecording=\(isRecording) isListening=\(isListening) — both true simultaneously")
        }
    }
}
