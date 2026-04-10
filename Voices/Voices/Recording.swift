import Foundation

struct Recording: Identifiable {
    let id: UUID
    var audioChunks: [AudioChunk] = []

    init(id: UUID = UUID(), audioChunks: [AudioChunk] = []) {
        self.id = id
        self.audioChunks = audioChunks
    }
}
