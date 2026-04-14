import Foundation
import Observation

@MainActor protocol PlaybackService: AnyObject {
    var playbackPosition: PlaybackPosition? { get }
    var isPlaying: Bool { get }
    func play(_ recordings: [Recording])
    func stop()
}

@Observable @MainActor
final class DemoPlaybackService: PlaybackService {
    private(set) var playbackPosition: PlaybackPosition?
    private(set) var isPlaying = false
    private var task: Task<Void, Never>?
    private let database: any Database

    init(database: any Database) {
        self.database = database
    }

    func play(_ recordings: [Recording]) {
        isPlaying = true
        let resume = resumePoint(in: recordings)
        if resume.recordingIndex < recordings.count {
            let position = PlaybackPosition(
                recordingID: recordings[resume.recordingIndex].id,
                chunkIndex: resume.chunkIndex
            )
            playbackPosition = position
            database.markListened(recordingID: position.recordingID, chunkIndex: position.chunkIndex)
        }
        task = Task { await consumePlayback(recordings, from: resume) }
    }

    func stop() {
        task?.cancel()
        task = nil
        isPlaying = false
    }

    private func resumePoint(in recordings: [Recording]) -> (recordingIndex: Int, chunkIndex: Int) {
        for (rIdx, recording) in recordings.enumerated() {
            for (cIdx, chunk) in recording.audioChunks.enumerated() {
                if !chunk.listened {
                    return (rIdx, cIdx)
                }
            }
        }
        return (recordings.count, 0)
    }

    private func consumePlayback(_ recordings: [Recording], from start: (recordingIndex: Int, chunkIndex: Int)) async {
        for recordingIndex in start.recordingIndex..<recordings.count {
            let recording = recordings[recordingIndex]
            let skipCount = (recordingIndex == start.recordingIndex) ? start.chunkIndex : 0
            let chunks = Array(recording.audioChunks.dropFirst(skipCount))

            for chunk in chunks {
                guard !Task.isCancelled else { return }
                try? await Task.sleep(for: .milliseconds(300))
                let position = PlaybackPosition(recordingID: recording.id, chunkIndex: chunk.index)
                playbackPosition = position
                database.markListened(recordingID: position.recordingID, chunkIndex: position.chunkIndex)
            }
        }

        if !Task.isCancelled {
            isPlaying = false
        }
    }
}

@Observable @MainActor
final class SilentPlaybackService: PlaybackService {
    private(set) var playbackPosition: PlaybackPosition?
    private(set) var isPlaying = false

    nonisolated init() {}

    func play(_ recordings: [Recording]) {
        isPlaying = true
    }

    func stop() {
        isPlaying = false
    }
}
