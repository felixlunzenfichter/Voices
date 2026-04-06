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

    /// Any uploaded chunks waiting to be heard?
    var hasListenable: Bool {
        true // Not implemented yet
    }

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

    // MARK: Listening (walks uploaded chunks oldest-first)

    private(set) var isListening = false
    private var listenTask: Task<Void, Never>?

    func startListening() {
        isListening = true
        listenTask = Task {
            while !Task.isCancelled {
                guard let (ri, ci) = oldestUploaded() else { break }
                recordings[ri].chunks[ci].status = .listened
                try? await Task.sleep(for: .milliseconds(100))
            }
            isListening = false
        }
    }

    func stopListening() {
        listenTask?.cancel()
        listenTask = nil
        isListening = false
    }

    private func oldestUploaded() -> (Int, Int)? {
        for ri in recordings.indices {
            if let ci = recordings[ri].chunks.firstIndex(where: { $0.status == .uploaded }) {
                return (ri, ci)
            }
        }
        return nil
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
