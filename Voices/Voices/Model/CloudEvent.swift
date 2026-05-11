import Foundation

/// One delta over the database. Wire payload between `PersistentDatabase`
/// and the Mac cloud. Each accepted event lands at a unique server-
/// assigned revision; the (revision, event) pair is the entry in the
/// server's append-only history.
///
/// Apply is idempotent for every case — re-applying a known event
/// produces the same state, which is what makes own-echo on broadcast
/// and CAS-retry-after-409 safe.
///
/// Wire shape (manual Codable so the JSON is portable to Node):
///   { "type": "recordingAdded", "recording": { id, author, audioChunks } }
///   { "type": "chunkAppended",  "recordingID": UUID, "chunk": { index, listened } }
///   { "type": "chunkListened",  "recordingID": UUID, "chunkIndex": Int, "by": UUID }
enum CloudEvent: Equatable, Sendable {
    case recordingAdded(Recording)
    case chunkAppended(recordingID: UUID, chunk: AudioChunk)
    case chunkListened(recordingID: UUID, chunkIndex: Int, by: UUID)
}

extension CloudEvent: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, recording, recordingID, chunk, chunkIndex, by
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "recordingAdded":
            self = .recordingAdded(try c.decode(Recording.self, forKey: .recording))
        case "chunkAppended":
            self = .chunkAppended(
                recordingID: try c.decode(UUID.self, forKey: .recordingID),
                chunk: try c.decode(AudioChunk.self, forKey: .chunk)
            )
        case "chunkListened":
            self = .chunkListened(
                recordingID: try c.decode(UUID.self, forKey: .recordingID),
                chunkIndex: try c.decode(Int.self, forKey: .chunkIndex),
                by: try c.decode(UUID.self, forKey: .by)
            )
        default:
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Unknown CloudEvent type: \(type)"
            ))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .recordingAdded(let r):
            try c.encode("recordingAdded", forKey: .type)
            try c.encode(r, forKey: .recording)
        case .chunkAppended(let id, let chunk):
            try c.encode("chunkAppended", forKey: .type)
            try c.encode(id, forKey: .recordingID)
            try c.encode(chunk, forKey: .chunk)
        case .chunkListened(let id, let idx, let by):
            try c.encode("chunkListened", forKey: .type)
            try c.encode(id, forKey: .recordingID)
            try c.encode(idx, forKey: .chunkIndex)
            try c.encode(by, forKey: .by)
        }
    }
}
