struct Chunk: Equatable {
    let index: Int
}

protocol ChunkProducer {
    func chunks() -> AsyncStream<Chunk>
}

struct SilentChunkProducer: ChunkProducer {
    func chunks() -> AsyncStream<Chunk> {
        AsyncStream { $0.finish() }
    }
}

struct DemoChunkProducer: ChunkProducer {
    func chunks() -> AsyncStream<Chunk> {
        AsyncStream { continuation in
            let task = Task {
                var index = 0
                while !Task.isCancelled {
                    continuation.yield(Chunk(index: index))
                    index += 1
                    try? await Task.sleep(for: .milliseconds(300))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
