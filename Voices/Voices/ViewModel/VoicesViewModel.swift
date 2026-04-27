import Foundation
import Observation

@Observable @MainActor
final class VoicesViewModel {
    var isRecording: Bool { recordingService.isRecording }
    var isListening: Bool { playbackService.isPlaying }
    var recordings: [Recording] {
        database.conversations.first(where: { $0.id == conversationID })?.recordings ?? []
    }
    var playbackPosition: PlaybackPosition? { playbackService.playbackPosition }

    let viewer: Participant
    let conversationID: UUID

    private let recordingService: any RecordingService
    private let playbackService: any PlaybackService
    private let database: any Database

    /// New, identity-bearing initializer.
    init(
        recordingService: any RecordingService,
        playbackService: any PlaybackService,
        database: any Database,
        viewer: Participant,
        conversationID: UUID
    ) {
        self.recordingService = recordingService
        self.playbackService = playbackService
        self.database = database
        self.viewer = viewer
        self.conversationID = conversationID
    }

    /// Legacy single-user initializer.
    convenience init(
        recordingService: any RecordingService,
        playbackService: any PlaybackService,
        database: any Database
    ) {
        let convoID = _legacyDefaultConversationID(in: database)
        self.init(
            recordingService: recordingService,
            playbackService: playbackService,
            database: database,
            viewer: .legacyViewer,
            conversationID: convoID
        )
    }

    // MARK: - State

    var totalChunkCount: Int {
        recordings.reduce(0) { $0 + $1.audioChunks.count }
    }

    /// Scrubber slot index: 0..<totalChunkCount for real chunks,
    /// totalChunkCount for the terminal (end) position.
    var scrubberIndex: Int {
        if let pos = playbackPosition {
            var index = 0
            for rec in recordings {
                if rec.id == pos.recordingID { return index + pos.chunkIndex }
                index += rec.audioChunks.count
            }
        }
        return totalChunkCount
    }

    /// User-visible chunk number, capped to the last real chunk.
    var displayChunkNumber: Int {
        min(scrubberIndex, max(totalChunkCount - 1, 0))
    }

    /// Foreign-authored content the viewer hasn't yet heard.
    var hasUnplayedChunks: Bool {
        recordings.contains { recording in
            recording.author != viewer.id
                && recording.audioChunks.contains { !$0.listenedBy.contains(viewer.id) }
        }
    }

    var canPlay: Bool {
        hasUnplayedChunks || playbackPosition != nil
    }

    private(set) var hasEverPlayed = false

    var canSeek: Bool {
        hasEverPlayed && !isListening && !isRecording && totalChunkCount > 0
    }

    var shouldAnimateChunks = true

    func isCurrent(recording: Recording, chunk: AudioChunk) -> Bool {
        guard let pos = playbackPosition else { return false }
        return pos.recordingID == recording.id && pos.chunkIndex == chunk.index
    }

    // MARK: - Actions

    func seekTo(_ globalIndex: Int) {
        let allChunks = recordings.flatMap { rec in
            rec.audioChunks.map { (rec.id, $0.index) }
        }
        guard !allChunks.isEmpty else { return }
        let clamped = max(0, min(globalIndex, allChunks.count))
        if clamped >= allChunks.count {
            playbackService.playbackPosition = nil
        } else {
            let (rid, idx) = allChunks[clamped]
            playbackService.playbackPosition = PlaybackPosition(recordingID: rid, chunkIndex: idx)
        }
    }

    func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    func toggleListening() {
        if isListening {
            stopListening()
        } else if hasUnplayedChunks || playbackPosition != nil {
            startListening()
        }
    }

    // MARK: - Recording

    private func startRecording() {
        if isListening { stopListening() }
        recordingService.start()
        log("Recording started")
    }

    private func stopRecording() {
        recordingService.stop()
        log("Recording stopped")
        sendNotification(title: "Recording", body: "Stopped")
    }

    // MARK: - Listening

    private func startListening() {
        if isRecording { stopRecording() }
        hasEverPlayed = true
        playbackService.play()
        log("Listening started")
    }

    private func stopListening() {
        playbackService.stop()
        log("Listening stopped")
    }
}
