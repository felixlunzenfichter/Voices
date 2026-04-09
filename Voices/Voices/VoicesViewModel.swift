import Observation

@Observable @MainActor
final class VoicesViewModel {
    private(set) var isRecording = false {
        didSet { checkMutualExclusion() }
    }
    private(set) var isListening = false {
        didSet { checkMutualExclusion() }
    }
    private(set) var recordings: [[AudioChunk]] = []
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

    // MARK: - Public

    var allChunks: [AudioChunk] {
        recordings.flatMap { $0 }
    }

    var hasUnplayedChunks: Bool {
        !allChunks.isEmpty && playbackIndex < allChunks.count - 1
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
        recordings.append([])
        recordingTask = Task { await consumeAudioChunks() }
        log("Recording started")
    }

    private func stopRecording() {
        cancelTask(&recordingTask)
        if recordings.last?.isEmpty ?? true {
            recordings.removeLast()
        }
        isRecording = false
        log("Recording stopped")
        sendNotification(title: "Recording", body: "Stopped")
    }

    private func consumeAudioChunks() async {
        for await audioChunk in recordingService.audioChunks() {
            guard !Task.isCancelled else { break }
            recordings[recordings.count - 1].append(audioChunk)
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
        let remaining = Array(allChunks.dropFirst(startIndex))
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
