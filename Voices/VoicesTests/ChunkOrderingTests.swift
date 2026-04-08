import Testing
@testable import Voices

struct FakeRecordingService: RecordingService {
    let count: Int

    func chunks() -> AsyncStream<Chunk> {
        let count = self.count
        return AsyncStream { continuation in
            Task {
                for i in 0..<count {
                    continuation.yield(Chunk(index: i))
                    await Task.yield()
                }
                continuation.finish()
            }
        }
    }
}

// MARK: - Pocket test: verify the fake itself

struct FakeRecordingServiceTests {
    @Test("Fake produces exactly N chunks in order", .timeLimit(.minutes(1)))
    func producesCorrectChunks() async {
        let producer = FakeRecordingService(count: 5)
        var collected: [Int] = []
        for await chunk in producer.chunks() {
            collected.append(chunk.index)
        }
        #expect(collected == [0, 1, 2, 3, 4])
    }

    @Test("Fake with zero count produces empty stream", .timeLimit(.minutes(1)))
    func zeroCountIsEmpty() async {
        let producer = FakeRecordingService(count: 0)
        var collected: [Chunk] = []
        for await chunk in producer.chunks() {
            collected.append(chunk)
        }
        #expect(collected.isEmpty)
    }
}


