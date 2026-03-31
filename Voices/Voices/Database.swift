import Foundation

// MARK: - Database Model (pure data, no local state)

struct Chunk: Identifiable {
    let id: UUID
    let seq: Int
    let data: Data          // Float32 PCM samples
}

struct Recording: Identifiable {
    let id: UUID
    let sampleRate: Int
    let channels: Int
    var chunks: [Chunk]
}

// MARK: - Database Protocol

@MainActor
protocol DatabaseProtocol {
    var recordings: [Recording] { get }
    func insertRecording(id: UUID, sampleRate: Int, channels: Int) -> Int
    func insertChunk(recordingIndex: Int, id: UUID, seq: Int, data: Data) -> Int
}

// MARK: - In-Memory Database

@Observable
@MainActor
final class Database: DatabaseProtocol {
    var recordings: [Recording] = []

    func insertRecording(id: UUID, sampleRate: Int, channels: Int) -> Int {
        let recording = Recording(
            id: id,
            sampleRate: sampleRate,
            channels: channels,
            chunks: []
        )
        recordings.append(recording)
        return recordings.count - 1
    }

    func insertChunk(recordingIndex: Int, id: UUID, seq: Int, data: Data) -> Int {
        let chunk = Chunk(id: id, seq: seq, data: data)
        recordings[recordingIndex].chunks.append(chunk)
        return recordings[recordingIndex].chunks.count - 1
    }
}
