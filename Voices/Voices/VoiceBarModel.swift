import SwiftUI

// MARK: - Status (grey → purple → blue)

enum ChunkStatus {
    case recorded  // grey  — captured, not yet uploaded
    case uploaded  // purple — on server, not yet listened
    case listened  // blue  — played back
}

extension ChunkStatus {
    var color: Color {
        switch self {
        case .recorded: return .gray
        case .uploaded: return .purple
        case .listened: return .blue
        }
    }
}

// MARK: - Data

struct ChunkEntry: Identifiable {
    let id: UUID
    var status: ChunkStatus
}

struct Recording: Identifiable {
    let id: UUID
    let createdAt: Date
    var chunks: [ChunkEntry]
}

// MARK: - Store (single source of truth)

@MainActor
@Observable
final class ChunkStore {
    private(set) var recordings: [Recording] = []
    private(set) var activeIndex: Int?  // index within current recording

    /// Chunks of the in-progress (or most recent) recording — drives the strip.
    var currentChunks: [ChunkEntry] {
        recordings.last?.chunks ?? []
    }

    func startRecording() {
        recordings.append(Recording(id: UUID(), createdAt: .now, chunks: []))
        activeIndex = nil
    }

    @discardableResult
    func appendChunk() -> UUID {
        guard !recordings.isEmpty else { return UUID() }
        let id = UUID()
        recordings[recordings.count - 1].chunks.append(ChunkEntry(id: id, status: .recorded))
        activeIndex = recordings[recordings.count - 1].chunks.count - 1
        scheduleUpload(id)
        return id
    }

    func stopRecording() {
        activeIndex = nil
    }

    func setStatus(_ id: UUID, _ status: ChunkStatus) {
        for ri in recordings.indices {
            if let ci = recordings[ri].chunks.firstIndex(where: { $0.id == id }) {
                recordings[ri].chunks[ci].status = status
                return
            }
        }
    }

    private func scheduleUpload(_ id: UUID) {
        Task {
            try? await Task.sleep(for: .seconds(3))
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
