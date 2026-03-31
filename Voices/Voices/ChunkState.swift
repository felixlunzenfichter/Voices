import Foundation
import Observation

// MARK: - Chunk lifecycle (local only, not persisted)

enum ChunkStatus {
    case recorded  // gray   — captured, not yet uploaded
    case uploaded  // purple — on server, not yet played
    case played    // blue   — played back
}

@Observable
@MainActor
final class ChunkStateTracker {
    private var states: [UUID: ChunkStatus] = [:]

    func status(of id: UUID) -> ChunkStatus {
        states[id] ?? .recorded
    }

    func markRecorded(_ id: UUID) {
        states[id] = .recorded
    }

    func markUploaded(_ id: UUID) {
        guard states[id] == .recorded else { return }
        states[id] = .uploaded
    }

    func markPlayed(_ id: UUID) {
        states[id] = .played
    }

    func hasPlayableChunks(in recording: Recording) -> Bool {
        recording.chunks.contains { status(of: $0.id) == .uploaded }
    }

    func markAllPlayed(in recording: Recording) {
        for chunk in recording.chunks {
            states[chunk.id] = .played
        }
    }

    // Streaming mock upload — fires per chunk during recording, not after
    func mockUpload(_ id: UUID) {
        Task {
            try? await Task.sleep(for: .seconds(3))
            self.markUploaded(id)
        }
    }
}
