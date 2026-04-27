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
