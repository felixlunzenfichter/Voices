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

    // MARK: - Self-test (runs on device, proves behavior via logs)

    #if DEBUG
    static func selfTest() async {
        let store = ChunkStore()

        // TEST 1: startRecording creates one recording
        store.startRecording()
        if store.recordings.count == 1 {
            log("TEST PASS: startRecording creates one recording (count=\(store.recordings.count))")
        } else {
            logError("TEST FAIL: startRecording should create one recording, got count=\(store.recordings.count)")
        }

        // TEST 2: appendChunk adds a chunk that can render as a bar
        store.appendChunk()
        if store.allChunks.count == 1 {
            log("TEST PASS: appendChunk adds one chunk for bar rendering (count=\(store.allChunks.count))")
        } else {
            logError("TEST FAIL: appendChunk should add one chunk for bar rendering, got count=\(store.allChunks.count)")
        }

        // TEST 3: simulate 1 second of recording, then check upload
        for _ in 0..<9 { store.appendChunk() }  // 10 chunks total
        log("TEST: recorded 10 chunks, waiting 2s for upload...")
        try? await Task.sleep(for: .seconds(2))
        let uploaded = store.allChunks.filter { $0.status == .uploaded }.count
        if uploaded > 0 {
            log("TEST PASS: \(uploaded)/\(store.allChunks.count) chunks uploaded (bars should turn purple)")
        } else {
            logError("TEST FAIL: 0/\(store.allChunks.count) chunks uploaded — no color change, upload not implemented")
        }
    }
    #endif
}
