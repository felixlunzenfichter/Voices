import Testing
@testable import Voices

struct FakeChunkProducer: ChunkProducer {
    let count: Int

    func chunks() -> AsyncStream<Chunk> {
        let count = self.count
        return AsyncStream { continuation in
            for i in 0..<count {
                continuation.yield(Chunk(index: i))
            }
            continuation.finish()
        }
    }
}

struct ChunkOrderingTests {
    @Test("Chunks arrive in sequential order during recording", .timeLimit(.minutes(1)))
    func chunksArriveInOrder() async {
        let producer = FakeChunkProducer(count: 5)
        let vm = VoicesViewModel(chunkProducer: producer)

        vm.toggleRecording()

        while vm.chunks.count < 5 {
            await Task.yield()
        }

        #expect(vm.chunks.map(\.index) == [0, 1, 2, 3, 4])
    }
}
