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

    /// Multi-user initializer. Caller specifies the conversation to
    /// record into and the author of the recordings being produced.
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

    /// Single-user-mode initializer. Records into the implicit solo
    /// conversation with `Participant.soloAuthor` as the author. The
    /// matching `DemoPlaybackService` solo init uses `Participant.solo`
    /// as the viewer; the two sentinels are deliberately distinct so
    /// the listenership rule "your own voice doesn't count" doesn't
    /// fire for solo-mode playback.
    convenience init(database: any Database, count: Int = .max, delay: Duration = .zero) {
        let convoID = soloConversationID(in: database)
        self.init(
            database: database,
            conversationID: convoID,
            authorID: Participant.soloAuthor.id,
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
