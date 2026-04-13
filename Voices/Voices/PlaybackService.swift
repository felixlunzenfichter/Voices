import Foundation
import Observation

@MainActor protocol PlaybackService: AnyObject {
    var playbackPosition: PlaybackPosition? { get }
    var isPlaying: Bool { get }
    func play(_ recordings: [Recording], from position: PlaybackPosition?)
    func stop()
}

@Observable @MainActor
final class DemoPlaybackService: PlaybackService {
    private(set) var playbackPosition: PlaybackPosition?
    private(set) var isPlaying = false
    private var task: Task<Void, Never>?

    nonisolated init() {}

    func play(_ recordings: [Recording], from position: PlaybackPosition?) {
        stop()
        isPlaying = true
        let resume = resumePoint(in: recordings, from: position)
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

    private func resumePoint(in recordings: [Recording], from position: PlaybackPosition?) -> (recordingIndex: Int, chunkIndex: Int) {
        guard let position,
              let index = recordings.firstIndex(where: { $0.id == position.recordingID })
        else { return (0, 0) }
        let nextChunk = position.chunkIndex + 1
        if nextChunk < recordings[index].audioChunks.count {
            return (index, nextChunk)
        }
        return (index + 1, 0)
    }

    private func consumePlayback(_ recordings: [Recording], from start: (recordingIndex: Int, chunkIndex: Int)) async {
        for recordingIndex in start.recordingIndex..<recordings.count {
            let recording = recordings[recordingIndex]
            let skipCount = (recordingIndex == start.recordingIndex) ? start.chunkIndex : 0
            let chunks = Array(recording.audioChunks.dropFirst(skipCount))

            for chunk in chunks {
                guard !Task.isCancelled else { return }
                try? await Task.sleep(for: .milliseconds(300))
                playbackPosition = PlaybackPosition(recordingID: recording.id, chunkIndex: chunk.index)
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

    func play(_ recordings: [Recording], from position: PlaybackPosition?) {
        isPlaying = true
    }

    func stop() {
        isPlaying = false
    }
}
