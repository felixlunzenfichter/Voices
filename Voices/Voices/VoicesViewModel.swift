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
    private let database: any Database
    private var recordingTask: Task<Void, Never>?
    private var playbackTask: Task<Void, Never>?

    init(
        recordingService: any RecordingService = SilentRecordingService(),
        playbackService: any PlaybackService = SilentPlaybackService(),
        database: any Database = InMemoryDatabase()
    ) {
        self.recordingService = recordingService
        self.playbackService = playbackService
        self.database = database
    }

    // MARK: - Public

    var hasUnplayedChunks: Bool {
        !audioChunks.isEmpty && playbackIndex < audioChunks.count - 1
    }

    func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    func toggleListening() {
        if isListening {
            stopListening()
        } else if hasUnplayedChunks {
            startListening()
        }
    }

    // MARK: - Recording

    private func startRecording() {
        if isListening { stopListening() }
        isRecording = true
        audioChunks = []
        recordingTask = Task { await consumeAudioChunks() }
        log("Recording started")
    }

    private func stopRecording() {
        cancelTask(&recordingTask)
        isRecording = false
        log("Recording stopped")
        sendNotification(title: "Recording", body: "Stopped")
    }

    private func consumeAudioChunks() async {
        for await audioChunk in recordingService.audioChunks() {
            guard !Task.isCancelled else { break }
            audioChunks.append(audioChunk)
        }
    }

    // MARK: - Listening

    private func startListening() {
        if isRecording { stopRecording() }
        isListening = true
        let startFrom = playbackIndex < 0 ? 0 : playbackIndex
        playbackIndex = startFrom
        playbackTask = Task { await consumePlayback(from: startFrom) }
        log("Listening started")
    }

    private func stopListening() {
        cancelTask(&playbackTask)
        isListening = false
        log("Listening stopped")
    }

    private func consumePlayback(from startIndex: Int) async {
        let remaining = Array(audioChunks.dropFirst(startIndex))
        for await index in playbackService.play(remaining) {
            guard !Task.isCancelled else { break }
            playbackIndex = index
        }
        if !Task.isCancelled {
            isListening = false
        }
    }

    // MARK: - Invariants

    private func checkMutualExclusion() {
        if isRecording && isListening {
            logError("INVARIANT: isRecording=\(isRecording) isListening=\(isListening) — both true simultaneously")
        }
    }

    // MARK: - Helpers

    private func cancelTask(_ task: inout Task<Void, Never>?) {
        task?.cancel()
        task = nil
    }
}
