import Foundation

// MARK: - Model

struct Recording: Identifiable {
    let id: UUID
    let sampleRate: Int
    let channels: Int
    var chunks: [Chunk]
}

struct Chunk: Identifiable {
    let id: UUID
    let seq: Int
    let data: Data  // Float32 PCM samples
}

// MARK: - Protocol

@MainActor
protocol DatabaseProtocol {
    var recordings: [Recording] { get }
    func insertRecording(id: UUID, sampleRate: Int, channels: Int)
    func insertChunk(recordingId: UUID, id: UUID, seq: Int, data: Data)
}

// MARK: - In-Memory Implementation

@Observable
@MainActor
final class Database: DatabaseProtocol {
    var recordings: [Recording] = []

    func insertRecording(id: UUID, sampleRate: Int, channels: Int) {
        recordings.append(Recording(id: id, sampleRate: sampleRate, channels: channels, chunks: []))
    }

    func insertChunk(recordingId: UUID, id: UUID, seq: Int, data: Data) {
        guard let index = recordings.firstIndex(where: { $0.id == recordingId }) else { return }
        recordings[index].chunks.append(Chunk(id: id, seq: seq, data: data))
    }
}
