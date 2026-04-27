import Foundation
import Observation

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
    private let conversationID: UUID
    private let authorID: UUID
    private var currentRecordingID: UUID?
    private var task: Task<Void, Never>?

    /// New, identity-bearing initializer.
    init(
        database: any Database,
        conversationID: UUID,
        authorID: UUID,
        count: Int = .max,
        delay: Duration = .zero
    ) {
        self.database = database
        self.conversationID = conversationID
        self.authorID = authorID
        self.count = count
        self.delay = delay
    }

    /// Legacy single-user initializer. Routes through the lazily-created
    /// default conversation and the legacy author identity so existing
    /// fixtures keep compiling and producing equivalent state.
    convenience init(database: any Database, count: Int = .max, delay: Duration = .zero) {
        let convoID = _legacyDefaultConversationID(in: database)
        self.init(
            database: database,
            conversationID: convoID,
            authorID: Participant.legacyAuthor.id,
            count: count,
            delay: delay
        )
    }

    func start() {
        isRecording = true
        let recording = Recording(author: authorID)
        currentRecordingID = recording.id
        database.addRecording(recording, to: conversationID)
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
        let convoRecordings = database.conversations.first(where: { $0.id == conversationID })?.recordings ?? []
        if convoRecordings.first(where: { $0.id == id })?.audioChunks.isEmpty == true {
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
            database.appendChunk(AudioChunk(index: index), to: recordingID, in: conversationID)
        }
    }
}
