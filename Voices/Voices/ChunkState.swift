import Foundation
import Observation

// MARK: - Local chunk lifecycle state (not persisted in database)

enum ChunkStatus {
    case recorded   // gray   — captured locally, not yet uploaded
    case uploaded   // purple — uploaded to server, not yet played
    case played     // blue   — has been played back
}

@Observable
@MainActor
final class ChunkStateTracker {
    private var states: [UUID: ChunkStatus] = [:]

    func status(of chunkId: UUID) -> ChunkStatus {
        states[chunkId] ?? .recorded
    }

    func markRecorded(_ chunkId: UUID) {
        states[chunkId] = .recorded
    }

    func markUploaded(_ chunkId: UUID) {
        guard states[chunkId] == .recorded else { return }
        states[chunkId] = .uploaded
    }

    func markPlayed(_ chunkId: UUID) {
        states[chunkId] = .played
    }

    func hasPlayableChunks(in recording: Recording) -> Bool {
        recording.chunks.contains { status(of: $0.id) == .uploaded }
    }

    func markAllPlayed(in recording: Recording) {
        for chunk in recording.chunks {
            states[chunk.id] = .played
        }
    }

    // MARK: - Mock Upload

    func mockUpload(_ chunkId: UUID) {
        Task {
            try? await Task.sleep(for: .seconds(3))
            self.markUploaded(chunkId)
        }
    }
}
