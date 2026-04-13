import Foundation
import Observation

protocol Database: AnyObject {
    var recordings: [Recording] { get }
    func addRecording(_ recording: Recording)
    func appendChunk(_ chunk: AudioChunk, to recordingID: UUID)
    func removeRecording(_ recordingID: UUID)
}

@Observable
final class InMemoryDatabase: Database {
    var recordings: [Recording] = []

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
}
