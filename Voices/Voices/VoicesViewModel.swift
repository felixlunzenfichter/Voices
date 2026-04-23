import Foundation
import Observation

@Observable @MainActor
final class VoicesViewModel {
    var isRecording: Bool { recordingService.isRecording }
    var isListening: Bool { playbackService.isPlaying }
    var recordings: [Recording] { database.recordings }
    var playbackPosition: PlaybackPosition? { playbackService.playbackPosition }

    private let recordingService: any RecordingService
    private let playbackService: any PlaybackService
    private let database: any Database

    init(
        recordingService: any RecordingService,
        playbackService: any PlaybackService,
        database: any Database
    ) {
        self.recordingService = recordingService
        self.playbackService = playbackService
        self.database = database
    }

    // MARK: - State

    var totalChunkCount: Int {
        recordings.reduce(0) { $0 + $1.audioChunks.count }
    }

    /// Honest cursor: nil when playbackPosition is nil (no active position).
    var cursorGlobalIndex: Int? {
        guard let pos = playbackPosition else { return nil }
        var index = 0
        for rec in recordings {
            if rec.id == pos.recordingID { return index + pos.chunkIndex }
            index += rec.audioChunks.count
        }
        return nil
    }

    /// Display index: always has a value for the UI. Shows cursorGlobalIndex
    /// when available, otherwise the last chunk (all listened) or 0 (empty).
    var displayIndex: Int {
        if let cursor = cursorGlobalIndex { return cursor }
        let total = totalChunkCount
        if total > 0 && !hasUnplayedChunks { return total - 1 }
        return 0
    }

    var hasUnplayedChunks: Bool {
        recordings.flatMap(\.audioChunks).contains { !$0.listened }
    }

    var canPlay: Bool {
        hasUnplayedChunks || playbackPosition != nil
    }

    var canSeek: Bool {
        !isListening && !isRecording && totalChunkCount > 0
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
        let clamped = max(0, min(globalIndex, allChunks.count - 1))
        let (rid, idx) = allChunks[clamped]
        playbackService.playbackPosition = PlaybackPosition(recordingID: rid, chunkIndex: idx)
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
        playbackService.play()
        log("Listening started")
    }

    private func stopListening() {
        playbackService.stop()
        log("Listening stopped")
    }

}
