import Foundation

struct AudioChunk: Equatable {
    let index: Int
    var listened: Bool = false
}

struct Recording: Identifiable {
    let id: UUID
    var author: UUID
    var audioChunks: [AudioChunk] = []

    init(id: UUID = UUID(), author: UUID = UUID(), audioChunks: [AudioChunk] = []) {
        self.id = id
        self.author = author
        self.audioChunks = audioChunks
    }
}
