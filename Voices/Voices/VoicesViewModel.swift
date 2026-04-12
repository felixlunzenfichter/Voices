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
    private(set) var playbackPosition: PlaybackPosition?

    var playbackIndex: Int { playbackPosition?.chunkIndex ?? -1 }

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
        guard totalChunks > 0 else { return false }
        guard let position = playbackPosition else { return true }
        // Find how many chunks come before and including the current position's recording
        guard let recordingIndex = recordings.firstIndex(where: { $0.id == position.recordingID }) else { return true }
        let chunksPlayedThrough = recordings.prefix(recordingIndex).reduce(0) { $0 + $1.audioChunks.count } + position.chunkIndex + 1
        return chunksPlayedThrough < totalChunks
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
        playbackTask = Task { await consumePlayback() }
        log("Listening started")
    }

    private func stopListening() {
        cancelTask(&playbackTask)
        isListening = false
        log("Listening stopped")
    }

    private func consumePlayback() async {
        let (startRecording, startChunk) = resumePoint()

        for recordingIndex in startRecording..<recordings.count {
            let skipCount = (recordingIndex == startRecording) ? startChunk : 0
            await playRecording(recordings[recordingIndex], startingAt: skipCount)
            guard !Task.isCancelled else { return }
        }

        if !Task.isCancelled {
            isListening = false
        }
    }

    private func resumePoint() -> (recordingIndex: Int, chunkIndex: Int) {
        guard let position = playbackPosition,
              let index = recordings.firstIndex(where: { $0.id == position.recordingID })
        else { return (0, 0) }
        return (index, position.chunkIndex)
    }

    private func playRecording(_ recording: Recording, startingAt chunkIndex: Int) async {
        let chunks = Array(recording.audioChunks.dropFirst(chunkIndex))
        for await index in playbackService.play(chunks) {
            guard !Task.isCancelled else { return }
            playbackPosition = PlaybackPosition(recordingID: recording.id, chunkIndex: index)
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
