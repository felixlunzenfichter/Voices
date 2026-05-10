import Foundation

struct AudioChunk: Equatable, Codable {
    let index: Int
    var listened: Bool = false
}

struct Recording: Identifiable, Equatable, Codable {
    let id: UUID
    var author: UUID
    var audioChunks: [AudioChunk] = []
    /// True iff *this device* has this recording saved on its disk.
    /// Per-device view, not canonical across instances.
    var isStoredLocally: Bool = false
    /// True iff *this device* has confirmed this recording is in the cloud.
    /// Per-device view, not canonical across instances.
    var isStoredRemotely: Bool = false

    init(id: UUID = UUID(),
         author: UUID = UUID(),
         audioChunks: [AudioChunk] = [],
         isStoredLocally: Bool = false,
         isStoredRemotely: Bool = false) {
        self.id = id
        self.author = author
        self.audioChunks = audioChunks
        self.isStoredLocally = isStoredLocally
        self.isStoredRemotely = isStoredRemotely
    }
}
