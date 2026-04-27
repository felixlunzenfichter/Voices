import Foundation

struct AudioChunk: Equatable {
    let index: Int
    var listenedBy: Set<UUID> = []

    /// Legacy single-user shorthand: any listener has heard the chunk.
    /// New per-listener checks should test `listenedBy.contains(viewerID)`.
    var listened: Bool { !listenedBy.isEmpty }
}

struct Recording: Identifiable {
    let id: UUID
    var author: UUID
    var audioChunks: [AudioChunk] = []

    init(
        id: UUID = UUID(),
        author: UUID = Participant.legacyAuthor.id,
        audioChunks: [AudioChunk] = []
    ) {
        self.id = id
        self.author = author
        self.audioChunks = audioChunks
    }
}
