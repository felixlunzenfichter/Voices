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

// MARK: - Store (single source of truth)

@MainActor
@Observable
final class ChunkStore {
    private(set) var chunks: [ChunkEntry] = []

    struct ChunkEntry: Identifiable {
        let id: UUID
        var status: ChunkStatus
    }

    /// Append a freshly recorded chunk (grey). Returns its ID.
    @discardableResult
    func appendRecorded() -> UUID {
        let id = UUID()
        chunks.append(ChunkEntry(id: id, status: .recorded))
        scheduleUpload(id)
        return id
    }

    func setStatus(_ id: UUID, _ status: ChunkStatus) {
        guard let i = chunks.firstIndex(where: { $0.id == id }) else { return }
        chunks[i].status = status
    }

    /// Mock upload: grey → purple after a short delay.
    private func scheduleUpload(_ id: UUID) {
        Task {
            try? await Task.sleep(for: .seconds(3))
            guard let i = chunks.firstIndex(where: { $0.id == id }),
                  chunks[i].status == .recorded else { return }
            chunks[i].status = .uploaded
        }
    }
}
