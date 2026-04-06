import SwiftUI

enum ChunkStatus {
    case recorded
    case uploaded
    case listened
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
        // Not implemented yet
    }

    // MARK: - Self-test (runs on device, proves behavior via logs)

    #if DEBUG
    static func selfTest() {
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
    }
    #endif
}
