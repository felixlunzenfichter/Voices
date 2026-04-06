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

    func startRecording() {
        recordings.append(Recording(id: UUID(), createdAt: .now, chunks: []))
    }

    // MARK: - Self-test (runs on device, proves behavior via logs)

    #if DEBUG
    static func selfTest() {
        let store = ChunkStore()

        // TEST: startRecording creates one recording
        store.startRecording()
        if store.recordings.count == 1 {
            log("TEST PASS: startRecording creates one recording (count=\(store.recordings.count))")
        } else {
            logError("TEST FAIL: startRecording should create one recording, got count=\(store.recordings.count)")
        }
    }
    #endif
}
