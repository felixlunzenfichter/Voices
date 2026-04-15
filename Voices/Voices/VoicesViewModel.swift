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

    // MARK: - Public

    var hasUnplayedChunks: Bool {
        recordings.flatMap(\.audioChunks).contains { !$0.listened }
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
