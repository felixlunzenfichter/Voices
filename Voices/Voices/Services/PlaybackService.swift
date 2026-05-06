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
    private(set) var playedChunks: [PlaybackPosition] = []
    private var task: Task<Void, Never>?
    private let database: any Database
    private let viewer: UUID

    private let delay: Duration

    init(database: any Database, viewer: UUID = UUID(), delay: Duration = .zero) {
        self.database = database
        self.viewer = viewer
        self.delay = delay
    }

    func play() {
        let recordings = database.recordings
        let resume: (recordingIndex: Int, chunkIndex: Int)
        if let pos = playbackPosition,
           let rIdx = recordings.firstIndex(where: { $0.id == pos.recordingID }) {
            resume = (rIdx, pos.chunkIndex)
        } else if let next = resumePoint(in: recordings) {
            resume = next
        } else {
            return
        }
        playedChunks = []
        isPlaying = true
        playbackPosition = PlaybackPosition(
            recordingID: recordings[resume.recordingIndex].id,
            chunkIndex: resume.chunkIndex
        )
        task = Task { await consumePlayback(recordings, from: resume) }
    }

    func stop() {
        task?.cancel()
        task = nil
        isPlaying = false
    }

    private func resumePoint(in recordings: [Recording]) -> (recordingIndex: Int, chunkIndex: Int)? {
        for (rIdx, recording) in recordings.enumerated() {
            guard recording.author != viewer else { continue }
            for (cIdx, chunk) in recording.audioChunks.enumerated() {
                if !chunk.listened {
                    return (rIdx, cIdx)
                }
            }
        }
        return nil
    }

    private func consumePlayback(_ recordings: [Recording], from start: (recordingIndex: Int, chunkIndex: Int)) async {
        for recordingIndex in start.recordingIndex..<recordings.count {
            let recordingID = recordings[recordingIndex].id
            var cIdx = (recordingIndex == start.recordingIndex) ? start.chunkIndex : 0
            // Re-read the live recording each iteration so chunks
            // appended to it during this session are picked up in the
            // same play, instead of the loop walking only the snapshot.
            while !Task.isCancelled {
                guard let recording = database.recordings.first(where: { $0.id == recordingID }),
                      cIdx < recording.audioChunks.count else { break }
                let chunk = recording.audioChunks[cIdx]
                if delay > .zero {
                    try? await Task.sleep(for: delay)
                } else {
                    await Task.yield()
                }
                guard !Task.isCancelled else { return }
                let position = PlaybackPosition(recordingID: recording.id, chunkIndex: chunk.index)
                playbackPosition = position
                playedChunks.append(position)
                database.markListened(recordingID: position.recordingID, chunkIndex: position.chunkIndex, by: viewer)
                cIdx += 1
            }
        }

        if !Task.isCancelled {
            await Task.yield()
            if let next = resumePoint(in: database.recordings) {
                playbackPosition = PlaybackPosition(
                    recordingID: database.recordings[next.recordingIndex].id,
                    chunkIndex: next.chunkIndex
                )
            } else {
                playbackPosition = nil
            }
            isPlaying = false
        }
    }
}
