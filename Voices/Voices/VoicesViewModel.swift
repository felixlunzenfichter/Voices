import Foundation
import Observation

@Observable @MainActor
final class VoicesViewModel {
    private(set) var isRecording = false {
        didSet { checkMutualExclusion() }
    }
    var isListening: Bool { playbackService.isPlaying }
    var recordings: [Recording] { database.recordings }
    var playbackPosition: PlaybackPosition? { playbackService.playbackPosition }

    private let recordingService: any RecordingService
    private let playbackService: any PlaybackService
    private let database: any Database
    private var currentRecordingID: UUID?
    private var recordingTask: Task<Void, Never>?

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
        let total = recordings.reduce(0) { $0 + $1.audioChunks.count }
        return total > 0 && chunksPlayedThrough < total
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
        removeCurrentRecordingIfEmpty()
        isRecording = false
        log("Recording stopped")
        sendNotification(title: "Recording", body: "Stopped")
    }

    private func removeCurrentRecordingIfEmpty() {
        guard let id = currentRecordingID,
              recordings.first(where: { $0.id == id })?.audioChunks.isEmpty == true
        else { return }
        database.removeRecording(id)
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
        playbackService.play(recordings, from: playbackPosition)
        log("Listening started")
    }

    private func stopListening() {
        playbackService.stop()
        log("Listening stopped")
    }

    // MARK: - Invariants

    private func checkMutualExclusion() {
        if isRecording && isListening {
            logError("INVARIANT: isRecording=\(isRecording) isListening=\(isListening) — both true simultaneously")
        }
    }

    // MARK: - Helpers

    private var chunksPlayedThrough: Int {
        guard let position = playbackPosition,
              let index = recordings.firstIndex(where: { $0.id == position.recordingID })
        else { return 0 }
        return recordings.prefix(index).reduce(0) { $0 + $1.audioChunks.count } + position.chunkIndex + 1
    }

    private func cancelTask(_ task: inout Task<Void, Never>?) {
        task?.cancel()
        task = nil
    }
}
