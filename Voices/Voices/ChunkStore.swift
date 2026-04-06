import SwiftUI

enum ChunkStatus {
    case recorded
    case uploaded
    case listened

    var color: Color {
        switch self {
        case .recorded: .gray
        case .uploaded: .purple
        case .listened: .blue
        }
    }
}

struct ChunkEntry: Identifiable {
    let id: UUID
    var status: ChunkStatus
}

struct Recording: Identifiable {
    let id: UUID
    let createdAt: Date
    var chunks: [ChunkEntry]
}

@Observable @MainActor
final class ChunkStore {
    private(set) var recordings: [Recording] = []

    /// All chunks flattened — drives the bar strip.
    var allChunks: [ChunkEntry] {
        recordings.flatMap(\.chunks)
    }

    func startRecording() {
        recordings.append(Recording(id: UUID(), createdAt: .now, chunks: []))
    }

    func appendChunk() {
        guard !recordings.isEmpty else { return }
        let id = UUID()
        recordings[recordings.count - 1].chunks.append(
            ChunkEntry(id: id, status: .recorded)
        )
        scheduleUpload(id)
    }

    private func scheduleUpload(_ id: UUID) {
        Task {
            try? await Task.sleep(for: .seconds(1))
            for ri in recordings.indices {
                if let ci = recordings[ri].chunks.firstIndex(where: { $0.id == id }),
                   recordings[ri].chunks[ci].status == .recorded {
                    recordings[ri].chunks[ci].status = .uploaded
                    return
                }
            }
        }
    }



}
