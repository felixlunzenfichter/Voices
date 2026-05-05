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
    let viewer: UUID

    init(
        recordingService: any RecordingService,
        playbackService: any PlaybackService,
        database: any Database,
        viewer: UUID = UUID()
    ) {
        self.recordingService = recordingService
        self.playbackService = playbackService
        self.database = database
        self.viewer = viewer
    }

    // MARK: - State

    // Memoized prefix-sum of chunk counts across `recordings`, plus
    // the running total. Lets `totalChunkCount`, `scrubberIndex`, and
    // `displayChunkNumber` answer in O(1) when the cache is fresh.
    // Invalidated lazily on the next read whenever `recordings.count`
    // or the last recording's chunk count changes — the only mutation
    // shapes the codebase produces today (append-only via
    // DemoRecordingService.produceChunks; new recordings appended via
    // DemoRecordingService.start). The cache fields are
    // ObservationIgnored so writing them does not invalidate observers.
    @ObservationIgnored
    private var cachedChunkOffsetsByID: [UUID: Int] = [:]
    @ObservationIgnored
    private var cachedTotalChunkCount: Int = 0
    @ObservationIgnored
    private var cachedRecordingsSignature: (count: Int, lastChunkCount: Int) = (0, 0)

    private func refreshOffsetCacheIfNeeded() {
        let recs = recordings
        let signature = (count: recs.count, lastChunkCount: recs.last?.audioChunks.count ?? 0)
        if signature == cachedRecordingsSignature { return }
        var offsets: [UUID: Int] = [:]
        offsets.reserveCapacity(recs.count)
        var running = 0
        for rec in recs {
            offsets[rec.id] = running
            running += rec.audioChunks.count
        }
        cachedChunkOffsetsByID = offsets
        cachedTotalChunkCount = running
        cachedRecordingsSignature = signature
    }

    var totalChunkCount: Int {
        refreshOffsetCacheIfNeeded()
        return cachedTotalChunkCount
    }

    /// Scrubber slot index: 0..<totalChunkCount for real chunks,
    /// totalChunkCount for the terminal (end) position.
    var scrubberIndex: Int {
        refreshOffsetCacheIfNeeded()
        if let pos = playbackPosition,
           let base = cachedChunkOffsetsByID[pos.recordingID] {
            return base + pos.chunkIndex
        }
        return cachedTotalChunkCount
    }

    /// User-visible chunk number, capped to the last real chunk.
    var displayChunkNumber: Int {
        min(scrubberIndex, max(totalChunkCount - 1, 0))
    }

    var hasUnplayedChunks: Bool {
        recordings.contains { recording in
            recording.author != viewer
                && recording.audioChunks.contains { !$0.listened }
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
