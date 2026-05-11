import Foundation

/// One delta over the database. Wire payload between `PersistentDatabase`
/// and the Mac cloud. Each accepted event lands at a unique server-
/// assigned revision; the (revision, event) pair is the entry in the
/// server's append-only history.
///
/// Apply is idempotent for every case — re-applying a known event
/// produces the same state, which is what makes own-echo on broadcast
/// and CAS-retry-after-409 safe.
enum CloudEvent: Codable, Equatable, Sendable {
    case recordingAdded(Recording)
    case chunkAppended(recordingID: UUID, chunk: AudioChunk)
    case chunkListened(recordingID: UUID, chunkIndex: Int, by: UUID)
}
