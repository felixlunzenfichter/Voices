import Foundation
import Observation

@MainActor protocol Database: AnyObject {
    /// All conversations in the database.
    var conversations: [Conversation] { get }

    /// Legacy convenience: all recordings flattened across every conversation.
    /// Single-user code paths read this directly. New multi-user code should
    /// reach into a specific `Conversation`.
    var recordings: [Recording] { get }

    func addConversation(_ conversation: Conversation)

    /// New, conversation-aware mutators.
    func addRecording(_ recording: Recording, to conversationID: UUID)
    func appendChunk(_ chunk: AudioChunk, to recordingID: UUID, in conversationID: UUID)
    func markListened(chunkIndex: Int, of recordingID: UUID, in conversationID: UUID, by listenerID: UUID)

    /// Legacy single-user mutators (route through a default conversation).
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

    // MARK: - New conversation-aware API

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
        conversations[cIdx].recordings[rIdx].audioChunks[chunkIndex].listenedBy.insert(listenerID)
    }

    // MARK: - Legacy single-user API

    func addRecording(_ recording: Recording) {
        addRecording(recording, to: defaultConversationID())
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
                conversations[cIdx].recordings[rIdx].audioChunks[chunkIndex].listenedBy.insert(Participant.legacyViewer.id)
                return
            }
        }
    }

    func removeRecording(_ recordingID: UUID) {
        for cIdx in conversations.indices {
            conversations[cIdx].recordings.removeAll { $0.id == recordingID }
        }
    }

    // MARK: - Default conversation (lazy, populated with legacy participants)

    func defaultConversationID() -> UUID {
        if let first = conversations.first { return first.id }
        let convo = Conversation(
            id: UUID(),
            participants: [Participant.legacyViewer, Participant.legacyAuthor],
            recordings: []
        )
        conversations.append(convo)
        return convo.id
    }
}

// MARK: - Helper used by legacy convenience inits across services / VM

@MainActor
internal func _legacyDefaultConversationID(in database: any Database) -> UUID {
    if let inMem = database as? InMemoryDatabase {
        return inMem.defaultConversationID()
    }
    if let firstID = database.conversations.first?.id {
        return firstID
    }
    let convo = Conversation(
        id: UUID(),
        participants: [Participant.legacyViewer, Participant.legacyAuthor],
        recordings: []
    )
    database.addConversation(convo)
    return convo.id
}
