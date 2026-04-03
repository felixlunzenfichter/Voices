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
    private(set) var isListening = false
    private var listenTask: Task<Void, Never>?

    /// All chunks flattened — drives the strip.
    var allChunks: [ChunkEntry] {
        recordings.flatMap(\.chunks)
    }

    /// Any purple chunks waiting to be heard?
    var hasListenable: Bool {
        recordings.contains { $0.chunks.contains { $0.status == .uploaded } }
    }

    // MARK: Recording

    func startRecording() {
        recordings.append(Recording(id: UUID(), createdAt: .now, chunks: []))
        activeIndex = nil
    }

    @discardableResult
    func appendChunk() -> UUID {
        guard !recordings.isEmpty else { return UUID() }
        let id = UUID()
        recordings[recordings.count - 1].chunks.append(ChunkEntry(id: id, status: .recorded))
        activeIndex = allChunks.count - 1
        scheduleUpload(id)
        return id
    }

    func stopRecording() {
        activeIndex = nil
    }

    // MARK: Listening (mock — walks purple chunks oldest-first)

    func startListening() {
        isListening = true
        listenTask = Task {
            while !Task.isCancelled {
                guard let (ri, ci) = oldestUploaded() else { break }
                activeIndex = globalIndex(ri, ci)
                recordings[ri].chunks[ci].status = .listened
                try? await Task.sleep(for: .milliseconds(100))
            }
            activeIndex = nil
            isListening = false
        }
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

    // MARK: Private

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
