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
        let resume = resumePoint()
        setPlaybackPosition(from: resume)
        playbackTask = Task { await consumePlayback(from: resume) }
        log("Listening started")
    }

    private func resumePoint() -> (recordingIndex: Int, chunkIndex: Int) {
        guard let position = playbackPosition,
              let index = recordings.firstIndex(where: { $0.id == position.recordingID })
        else { return (0, 0) }
        let nextChunk = position.chunkIndex + 1
        if nextChunk < recordings[index].audioChunks.count {
            return (index, nextChunk)
        }
        return (index + 1, 0)
    }

    private func setPlaybackPosition(from point: (recordingIndex: Int, chunkIndex: Int)) {
        guard point.recordingIndex < recordings.count else { return }
        playbackPosition = PlaybackPosition(
            recordingID: recordings[point.recordingIndex].id,
            chunkIndex: point.chunkIndex
        )
    }

    private func consumePlayback(from start: (recordingIndex: Int, chunkIndex: Int)) async {
        for recordingIndex in start.recordingIndex..<recordings.count {
            let skipCount = (recordingIndex == start.recordingIndex) ? start.chunkIndex : 0
            await playRecording(recordings[recordingIndex], startingAt: skipCount)
            guard !Task.isCancelled else { return }
        }

        if !Task.isCancelled {
            isListening = false
        }
    }

    private func playRecording(_ recording: Recording, startingAt chunkIndex: Int) async {
        let chunks = Array(recording.audioChunks.dropFirst(chunkIndex))
        for await index in playbackService.play(chunks) {
            guard !Task.isCancelled else { return }
            playbackPosition = PlaybackPosition(recordingID: recording.id, chunkIndex: index)
        }
    }

    private func stopListening() {
        cancelTask(&playbackTask)
        isListening = false
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
