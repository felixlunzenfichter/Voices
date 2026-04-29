import Foundation

struct AudioChunk: Equatable {
    let index: Int
    var listenedBy: Set<UUID> = []

    /// Single-user-mode shorthand: in solo mode there is at most one
    /// possible listener, so "any listener has heard this chunk" and
    /// "the viewer has heard this chunk" coincide. Multi-user code
    /// should always test `listenedBy.contains(viewerID)` directly.
    var listened: Bool { !listenedBy.isEmpty }
}

struct Recording: Identifiable {
    let id: UUID
    var author: UUID
    var audioChunks: [AudioChunk] = []

    init(
        id: UUID = UUID(),
        author: UUID = Participant.soloAuthor.id,
        audioChunks: [AudioChunk] = []
    ) {
        self.id = id
        self.author = author
        self.audioChunks = audioChunks
    }
}
