import Observation

protocol Database: AnyObject {
    var recordings: [Recording] { get }
    func addRecording(_ recording: Recording)
}

@Observable
final class InMemoryDatabase: Database {
    var recordings: [Recording] = []

    func addRecording(_ recording: Recording) {
        recordings.append(recording)
    }
}
