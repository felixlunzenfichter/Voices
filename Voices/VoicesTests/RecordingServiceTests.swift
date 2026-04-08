import Testing
@testable import Voices

struct FakeRecordingService: RecordingService {
    let count: Int

    func audioChunks() -> AsyncStream<AudioChunk> {
        let count = self.count
        return AsyncStream { continuation in
            Task {
                for i in 0..<count {
                    continuation.yield(AudioChunk(index: i))
                    await Task.yield()
                }
                continuation.finish()
            }
        }
    }
}


