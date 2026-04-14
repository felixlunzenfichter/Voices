import Foundation
import Observation

@MainActor protocol Database: AnyObject {
    var recordings: [Recording] { get }
    func addRecording(_ recording: Recording)
    func appendChunk(_ chunk: AudioChunk, to recordingID: UUID)
    func removeRecording(_ recordingID: UUID)
    func markListened(recordingID: UUID, chunkIndex: Int)
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
}
