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
        recordingService.start(into: database)
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
        playbackService.play(recordings)
        log("Listening started")
    }

    private func stopListening() {
        playbackService.stop()
        log("Listening stopped")
    }

    // MARK: - Helpers

    private var chunksPlayedThrough: Int {
        guard let position = playbackPosition,
              let index = recordings.firstIndex(where: { $0.id == position.recordingID })
        else { return 0 }
        return recordings.prefix(index).reduce(0) { $0 + $1.audioChunks.count } + position.chunkIndex + 1
    }
}
