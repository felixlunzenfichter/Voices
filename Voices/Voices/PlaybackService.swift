import Foundation
import Observation

@MainActor protocol PlaybackService: AnyObject {
    var playbackPosition: PlaybackPosition? { get set }
    var isPlaying: Bool { get }
    func play()
    func stop()
}

@Observable @MainActor
final class DemoPlaybackService: PlaybackService {
    var playbackPosition: PlaybackPosition?
    private(set) var isPlaying = false
    private var task: Task<Void, Never>?
    private let database: any Database

    private let delay: Duration

    init(database: any Database, delay: Duration = .zero) {
        self.database = database
        self.delay = delay
    }

    func play() {
        let recordings = database.recordings
        isPlaying = true
        let resume = resumePoint(in: recordings)
        if resume.recordingIndex < recordings.count {
            playbackPosition = PlaybackPosition(
                recordingID: recordings[resume.recordingIndex].id,
                chunkIndex: resume.chunkIndex
            )
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
                if delay > .zero {
                    try? await Task.sleep(for: delay)
                } else {
                    await Task.yield()
                }
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
