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

// MARK: - VoicesViewModel fixture for "viewer hears a foreign message"

extension VoicesViewModel {
    /// A viewer with one foreign-authored recording of `chunkCount` chunks
    /// already in the conversation. Returned tuple lets the test inspect
    /// chunk-level state without re-deriving ids.
    @MainActor
    static func viewerWithForeignMessage(
        viewer: Participant = .mama,
        author: Participant = .marina,
        chunkCount: Int
    ) -> (vm: VoicesViewModel, db: InMemoryDatabase) {
        let recording = Recording(author: author.id,
                                  audioChunks: (0..<chunkCount).map { AudioChunk(index: $0) })
        let conversation = Conversation(
            id: UUID(),
            participants: [viewer, author],
            recordings: [recording]
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
