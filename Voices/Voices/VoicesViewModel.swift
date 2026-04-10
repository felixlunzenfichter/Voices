import Foundation
import Observation

@Observable @MainActor
final class VoicesViewModel {
    private(set) var isRecording = false {
        didSet { checkMutualExclusion() }
    }
    private(set) var isListening = false {
        didSet { checkMutualExclusion() }
    }
    var recordings: [Recording] { database.recordings }
    private(set) var playbackIndex: Int = -1

    private let recordingService: any RecordingService
    private let playbackService: any PlaybackService
    private let database: any Database
    private var currentRecordingID: UUID?
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
        let totalChunks = recordings.reduce(0) { $0 + $1.audioChunks.count }
        return totalChunks > 0 && playbackIndex < totalChunks - 1
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
        let recording = Recording()
        currentRecordingID = recording.id
        database.addRecording(recording)
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
        guard let recordingID = currentRecordingID else { return }
        for await audioChunk in recordingService.audioChunks() {
            guard !Task.isCancelled else { break }
            database.appendChunk(audioChunk, to: recordingID)
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
        let remaining = Array((recordings.last?.audioChunks ?? []).dropFirst(startIndex))
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
