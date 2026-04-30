import Foundation
@testable import Voices

// MARK: - Identity fixtures
//
// `mama` and `marina` stand in for any two real people. Tests that don't
// care about identity should never need to mention them — the helpers below
// hide all conversation/participant wiring behind viewer-shaped fixtures.

extension Participant {
    static let mama   = Participant(id: UUID(), displayName: "Mama")
    static let marina = Participant(id: UUID(), displayName: "Marina")
}

// MARK: - VoicesViewModel fixtures by message ownership

extension VoicesViewModel {
    /// A viewer with one foreign-authored recording of `chunkCount` chunks
    /// already in the conversation.
    @MainActor
    static func viewerWithForeignMessage(
        viewer: Participant = .mama,
        author: Participant = .marina,
        chunkCount: Int
    ) -> (vm: VoicesViewModel, db: InMemoryDatabase) {
        let recording = Recording(author: author.id,
                                  audioChunks: (0..<chunkCount).map { AudioChunk(index: $0) })
        return _viewerFixture(
            viewer: viewer,
            participants: [viewer, author],
            recordings: [recording]
        )
    }

    /// A viewer with one of their own recordings of `chunkCount` chunks
    /// already in the conversation. Used to pin down the rule that hearing
    /// your own voice doesn't count as listening.
    @MainActor
    static func viewerWithOwnMessage(
        viewer: Participant = .mama,
        chunkCount: Int
    ) -> (vm: VoicesViewModel, db: InMemoryDatabase) {
        let recording = Recording(author: viewer.id,
                                  audioChunks: (0..<chunkCount).map { AudioChunk(index: $0) })
        return _viewerFixture(
            viewer: viewer,
            participants: [viewer],
            recordings: [recording]
        )
    }

    /// Two viewers sharing one conversation, plus one foreign-authored
    /// recording the listener can play. Each viewer gets its own VM
    /// pointed at the shared database. Used to pin down what one viewer
    /// can observe about the other while the other is listening — the
    /// predicate behind the "other cursor" UI state.
    @MainActor
    static func pairOfViewers(
        recorder: Participant = .marina,
        listener: Participant = .mama,
        chunkCount: Int
    ) -> (recorderVM: VoicesViewModel, listenerVM: VoicesViewModel, db: InMemoryDatabase) {
        let recording = Recording(
            author: recorder.id,
            audioChunks: (0..<chunkCount).map { AudioChunk(index: $0) }
        )
        let conversation = Conversation(
            id: UUID(),
            participants: [recorder, listener],
            recordings: [recording]
        )
        let db = InMemoryDatabase()
        db.addConversation(conversation)

        let recorderVM = VoicesViewModel(
            recordingService: DemoRecordingService(
                database: db, conversationID: conversation.id, authorID: recorder.id
            ),
            playbackService: DemoPlaybackService(
                database: db, conversationID: conversation.id, viewerID: recorder.id
            ),
            database: db,
            viewer: recorder,
            conversationID: conversation.id
        )
        let listenerVM = VoicesViewModel(
            recordingService: DemoRecordingService(
                database: db, conversationID: conversation.id, authorID: listener.id
            ),
            playbackService: DemoPlaybackService(
                database: db, conversationID: conversation.id, viewerID: listener.id
            ),
            database: db,
            viewer: listener,
            conversationID: conversation.id
        )
        return (recorderVM, listenerVM, db)
    }

    @MainActor
    private static func _viewerFixture(
        viewer: Participant,
        participants: [Participant],
        recordings: [Recording]
    ) -> (vm: VoicesViewModel, db: InMemoryDatabase) {
        let conversation = Conversation(
            id: UUID(),
            participants: participants,
            recordings: recordings
        )
        let db = InMemoryDatabase()
        db.addConversation(conversation)
        let rec = DemoRecordingService(database: db,
                                       conversationID: conversation.id,
                                       authorID: viewer.id)
        let play = DemoPlaybackService(database: db,
                                       conversationID: conversation.id,
                                       viewerID: viewer.id)
        let vm = VoicesViewModel(
            recordingService: rec,
            playbackService: play,
            database: db,
            viewer: viewer,
            conversationID: conversation.id
        )
        return (vm, db)
    }
}
