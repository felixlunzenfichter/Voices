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
    private let conversationID: UUID
    private let viewerID: UUID
    private let delay: Duration

    /// New, identity-bearing initializer.
    init(
        database: any Database,
        conversationID: UUID,
        viewerID: UUID,
        delay: Duration = .zero
    ) {
        self.database = database
        self.conversationID = conversationID
        self.viewerID = viewerID
        self.delay = delay
    }

    /// Legacy single-user initializer. Routes through the lazily-created
    /// default conversation and the legacy viewer identity.
    convenience init(database: any Database, delay: Duration = .zero) {
        let convoID = _legacyDefaultConversationID(in: database)
        self.init(
            database: database,
            conversationID: convoID,
            viewerID: Participant.legacyViewer.id,
            delay: delay
        )
    }

    func play() {
        let recordings = currentRecordings()
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

    // MARK: - Private

    private func currentRecordings() -> [Recording] {
        database.conversations.first(where: { $0.id == conversationID })?.recordings ?? []
    }

    /// First chunk that the viewer hasn't listened to yet, in any foreign
    /// recording. Own recordings are skipped — hearing your own voice
    /// doesn't count.
    private func resumePoint(in recordings: [Recording]) -> (recordingIndex: Int, chunkIndex: Int)? {
        for (rIdx, recording) in recordings.enumerated() {
            guard recording.author != viewerID else { continue }
            for (cIdx, chunk) in recording.audioChunks.enumerated() {
                if !chunk.listenedBy.contains(viewerID) {
                    return (rIdx, cIdx)
                }
            }
        }
        return nil
    }

    private func consumePlayback(
        _ recordings: [Recording],
        from start: (recordingIndex: Int, chunkIndex: Int)
    ) async {
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
                guard !Task.isCancelled else { return }
                let position = PlaybackPosition(recordingID: recording.id, chunkIndex: chunk.index)
                playbackPosition = position
                playedChunks.append(position)

                // Mark listened only when the viewer is *not* the author.
                if recording.author != viewerID {
                    database.markListened(
                        chunkIndex: chunk.index,
                        of: recording.id,
                        in: conversationID,
                        by: viewerID
                    )
                }
            }
        }

        if !Task.isCancelled {
            await Task.yield()
            let after = currentRecordings()
            if let next = resumePoint(in: after) {
                playbackPosition = PlaybackPosition(
                    recordingID: after[next.recordingIndex].id,
                    chunkIndex: next.chunkIndex
                )
            } else {
                playbackPosition = nil
            }
            isPlaying = false
        }
    }
}
