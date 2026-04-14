import Foundation
import Observation

struct AudioChunk: Equatable {
    let index: Int
    var listened: Bool = false
}

@MainActor protocol RecordingService: AnyObject {
    var isRecording: Bool { get }
    func start()
    func stop()
}

@Observable @MainActor
final class DemoRecordingService: RecordingService {
    private(set) var isRecording = false
    private let count: Int
    private let delay: Duration
    private let database: any Database
    private var currentRecordingID: UUID?
    private var task: Task<Void, Never>?

    init(database: any Database, count: Int = .max, delay: Duration = .zero) {
        self.database = database
        self.count = count
        self.delay = delay
    }

    func start() {
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
        isRecording = false
    }

    private func removeCurrentRecordingIfEmpty() {
        guard let id = currentRecordingID else { return }
        if database.recordings.first(where: { $0.id == id })?.audioChunks.isEmpty == true {
            database.removeRecording(id)
        }
    }

    private func produceChunks() async {
        guard let recordingID = currentRecordingID else { return }
        for index in 0..<count {
            if delay > .zero {
                try? await Task.sleep(for: delay)
            } else {
                await Task.yield()
            }
            guard !Task.isCancelled else { break }
            database.appendChunk(AudioChunk(index: index), to: recordingID)
        }
    }
}

@Observable @MainActor
final class SilentRecordingService: RecordingService {
    private(set) var isRecording = false

    nonisolated init() {}

    func start() {
        isRecording = true
    }

    func stop() {
        isRecording = false
    }
}
