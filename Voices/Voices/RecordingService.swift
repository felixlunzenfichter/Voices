import Foundation
import Observation

struct AudioChunk: Equatable {
    let index: Int
}

@MainActor protocol RecordingService: AnyObject {
    var isRecording: Bool { get }
    func start(into database: any Database)
    func stop()
}

@Observable @MainActor
final class DemoRecordingService: RecordingService {
    private(set) var isRecording = false
    private var currentRecordingID: UUID?
    private weak var database: (any Database)?
    private var task: Task<Void, Never>?

    func start(into database: any Database) {
        self.database = database
        isRecording = true
        let recording = Recording()
        currentRecordingID = recording.id
        database.addRecording(recording)
        task = Task { await produceChunks() }
    }

    func stop() {
        task?.cancel()
        task = nil
        removeCurrentRecordingIfEmpty()
        currentRecordingID = nil
        database = nil
        isRecording = false
    }

    private func removeCurrentRecordingIfEmpty() {
        guard let id = currentRecordingID, let database else { return }
        if database.recordings.first(where: { $0.id == id })?.audioChunks.isEmpty == true {
            database.removeRecording(id)
        }
    }

    private func produceChunks() async {
        guard let recordingID = currentRecordingID else { return }
        var index = 0
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { break }
            database?.appendChunk(AudioChunk(index: index), to: recordingID)
            index += 1
        }
    }
}

@Observable @MainActor
final class SilentRecordingService: RecordingService {
    private(set) var isRecording = false

    nonisolated init() {}

    func start(into database: any Database) {
        isRecording = true
    }

    func stop() {
        isRecording = false
    }
}
