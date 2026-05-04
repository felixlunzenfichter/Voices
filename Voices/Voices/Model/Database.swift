import Foundation
import Observation

@MainActor protocol Database: AnyObject {
    var recordings: [Recording] { get }
    func addRecording(_ recording: Recording)
    func appendChunk(_ chunk: AudioChunk, to recordingID: UUID)
    func removeRecording(_ recordingID: UUID)
    func markListened(recordingID: UUID, chunkIndex: Int)
    func markListened(recordingID: UUID, chunkIndex: Int, by viewerID: UUID)
}

@Observable @MainActor
final class InMemoryDatabase: Database {
    var recordings: [Recording] = []

    nonisolated init() {}

    func addRecording(_ recording: Recording) {
        recordings.append(recording)
    }

    func appendChunk(_ chunk: AudioChunk, to recordingID: UUID) {
        guard let index = recordings.firstIndex(where: { $0.id == recordingID }) else { return }
        recordings[index].audioChunks.append(chunk)
    }

    func removeRecording(_ recordingID: UUID) {
        recordings.removeAll { $0.id == recordingID }
    }

    func markListened(recordingID: UUID, chunkIndex: Int) {
        guard let rIdx = recordings.firstIndex(where: { $0.id == recordingID }),
              chunkIndex < recordings[rIdx].audioChunks.count else { return }
        recordings[rIdx].audioChunks[chunkIndex].listened = true
    }

    /// Author-aware mark: a viewer who is the recording's author cannot
    /// turn their own chunk listened. Otherwise marks it listened.
    func markListened(recordingID: UUID, chunkIndex: Int, by viewerID: UUID) {
        guard let rIdx = recordings.firstIndex(where: { $0.id == recordingID }),
              chunkIndex < recordings[rIdx].audioChunks.count,
              recordings[rIdx].author != viewerID else { return }
        recordings[rIdx].audioChunks[chunkIndex].listened = true
    }
}
