import Foundation
import Observation

@MainActor protocol Database: AnyObject {
    /// All conversations in the database.
    var conversations: [Conversation] { get }

    /// Single-user-mode convenience: all recordings flattened across every
    /// conversation. In solo mode there is exactly one conversation, so
    /// this is just "the recordings." Multi-user code should reach into
    /// a specific `Conversation` instead.
    var recordings: [Recording] { get }

    func addConversation(_ conversation: Conversation)

    /// Multi-user, conversation-aware mutators. These are the canonical
    /// API; the single-user-mode mutators below delegate to these via
    /// the implicit solo conversation.
    func addRecording(_ recording: Recording, to conversationID: UUID)
    func appendChunk(_ chunk: AudioChunk, to recordingID: UUID, in conversationID: UUID)
    func markListened(chunkIndex: Int, of recordingID: UUID, in conversationID: UUID, by listenerID: UUID)

    /// Single-user-mode mutators. They route through the implicit solo
    /// conversation (created lazily on first use) so callers that don't
    /// care about identity can stay terse.
    func addRecording(_ recording: Recording)
    func appendChunk(_ chunk: AudioChunk, to recordingID: UUID)
    func markListened(recordingID: UUID, chunkIndex: Int)

    func removeRecording(_ recordingID: UUID)
}

@Observable @MainActor
final class InMemoryDatabase: Database {
    var conversations: [Conversation] = []

    nonisolated init() {}

    var recordings: [Recording] {
        conversations.flatMap { $0.recordings }
    }

    func addConversation(_ conversation: Conversation) {
        conversations.append(conversation)
    }

    // MARK: - Multi-user, conversation-aware API

    func addRecording(_ recording: Recording, to conversationID: UUID) {
        guard let cIdx = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        conversations[cIdx].recordings.append(recording)
    }

    func appendChunk(_ chunk: AudioChunk, to recordingID: UUID, in conversationID: UUID) {
        guard let cIdx = conversations.firstIndex(where: { $0.id == conversationID }),
              let rIdx = conversations[cIdx].recordings.firstIndex(where: { $0.id == recordingID })
        else { return }
        conversations[cIdx].recordings[rIdx].audioChunks.append(chunk)
    }

    func markListened(
        chunkIndex: Int,
        of recordingID: UUID,
        in conversationID: UUID,
        by listenerID: UUID
    ) {
        guard let cIdx = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        // Defensive: only allow listeners that are participants of the conversation.
        guard conversations[cIdx].participants.contains(where: { $0.id == listenerID }) else { return }
        guard let rIdx = conversations[cIdx].recordings.firstIndex(where: { $0.id == recordingID }),
              chunkIndex >= 0,
              chunkIndex < conversations[cIdx].recordings[rIdx].audioChunks.count
        else { return }
        conversations[cIdx].recordings[rIdx].audioChunks[chunkIndex].listenCounts[listenerID, default: 0] += 1
    }

    // MARK: - Single-user-mode API
    //
    // These mutators target the implicit solo conversation, created on
    // first use. They keep call sites short for code that only ever runs
    // in single-user mode (one device, one author == viewer == `.solo`).

    func addRecording(_ recording: Recording) {
        addRecording(recording, to: soloConversationID())
    }

    func appendChunk(_ chunk: AudioChunk, to recordingID: UUID) {
        for cIdx in conversations.indices {
            if let rIdx = conversations[cIdx].recordings.firstIndex(where: { $0.id == recordingID }) {
                conversations[cIdx].recordings[rIdx].audioChunks.append(chunk)
                return
            }
        }
    }

    func markListened(recordingID: UUID, chunkIndex: Int) {
        for cIdx in conversations.indices {
            if let rIdx = conversations[cIdx].recordings.firstIndex(where: { $0.id == recordingID }),
               chunkIndex >= 0,
               chunkIndex < conversations[cIdx].recordings[rIdx].audioChunks.count {
                conversations[cIdx].recordings[rIdx].audioChunks[chunkIndex].listenCounts[Participant.solo.id, default: 0] += 1
                return
            }
        }
    }

    func removeRecording(_ recordingID: UUID) {
        for cIdx in conversations.indices {
            conversations[cIdx].recordings.removeAll { $0.id == recordingID }
        }
    }

    // MARK: - Solo conversation (single-user mode)
    //
    // Single-user mode runs in one implicit conversation with one
    // participant (`Participant.solo`) who is both author and viewer.
    // Created on first use so single-user callers never have to
    // construct a `Conversation` themselves.

    func soloConversationID() -> UUID {
        if let first = conversations.first { return first.id }
        let convo = Conversation(
            id: UUID(),
            participants: [Participant.solo, Participant.soloAuthor],
            recordings: []
        )
        conversations.append(convo)
        return convo.id
    }
}

// MARK: - Single-user-mode helper
//
// Used by the single-user convenience inits on `VoicesViewModel`,
// `DemoPlaybackService`, and `DemoRecordingService`. Returns the ID of
// the implicit solo conversation, creating it on first use.

@MainActor
internal func soloConversationID(in database: any Database) -> UUID {
    if let inMem = database as? InMemoryDatabase {
        return inMem.soloConversationID()
    }
    if let firstID = database.conversations.first?.id {
        return firstID
    }
    let convo = Conversation(
        id: UUID(),
        participants: [Participant.solo, Participant.soloAuthor],
        recordings: []
    )
    database.addConversation(convo)
    return convo.id
}
