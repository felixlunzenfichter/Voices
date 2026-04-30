import Foundation

struct AudioChunk: Equatable {
    let index: Int

    /// Per-participant listen count. Each `markListened` heartbeat
    /// increments the entry for that participant; replaying the same
    /// chunk produces a higher count, not a deduped membership.
    var listenCounts: [UUID: Int] = [:]

    /// Membership projection over `listenCounts` — present iff that
    /// participant has heard the chunk at least once. Existing call
    /// sites that only need "did anyone (or did this person) hear it"
    /// keep working unchanged through this Set view.
    var listenedBy: Set<UUID> {
        Set(listenCounts.compactMap { $0.value > 0 ? $0.key : nil })
    }

    /// Single-user-mode shorthand: in solo mode there is at most one
    /// possible listener, so "any listener has heard this chunk" and
    /// "the viewer has heard this chunk" coincide. Multi-user code
    /// should always test `listenedBy.contains(viewerID)` directly.
    var listened: Bool { !listenCounts.isEmpty }

    /// How many times the given participant has listened to this chunk.
    /// Reads directly from the count storage, so repeated heartbeats
    /// from the same participant accumulate.
    func listenCount(by participantID: UUID) -> Int {
        listenCounts[participantID] ?? 0
    }
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
