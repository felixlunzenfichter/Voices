import Foundation

struct AudioChunk: Equatable {
    let index: Int
    var listened: Bool = false
}

struct Recording: Identifiable {
    let id: UUID
    var audioChunks: [AudioChunk] = []

    init(id: UUID = UUID(), audioChunks: [AudioChunk] = []) {
        self.id = id
        self.audioChunks = audioChunks
    }
}
