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
    private(set) var activeIndex: Int?  // chunk the view should center on
    private let db: ListenedDatabase

    init(db: ListenedDatabase = InMemoryListenedDatabase()) {
        self.db = db
    }

    /// Any uploaded chunks waiting to be heard?
    var hasListenable: Bool {
        recordings.contains { $0.chunks.contains { $0.status == .uploaded } }
    }

    /// Has every chunk been listened to at least once? (persistent — survives scrub)
    var allHeard: Bool {
        db.allHeard(allChunks.map(\.id))
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
        activeIndex = allChunks.count - 1
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
                activeIndex = globalIndex(ri, ci)
                recordings[ri].chunks[ci].status = .listened
                db.markHeard(recordings[ri].chunks[ci].id)
                try? await Task.sleep(for: .milliseconds(100))
            }
            activeIndex = nil
            isListening = false
        }
    }

    // MARK: Scrubbing

    func previewScrub(_ globalIndex: Int) {
        var gi = 0
        for ri in recordings.indices {
            for ci in recordings[ri].chunks.indices {
                if recordings[ri].chunks[ci].status != .recorded {
                    recordings[ri].chunks[ci].status = gi <= globalIndex ? .listened : .uploaded
                }
                gi += 1
            }
        }
    }

    func scrubTo(_ globalIndex: Int) {
        activeIndex = globalIndex
        previewScrub(globalIndex)
    }

    private func globalIndex(_ ri: Int, _ ci: Int) -> Int {
        recordings[..<ri].reduce(0) { $0 + $1.chunks.count } + ci
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
