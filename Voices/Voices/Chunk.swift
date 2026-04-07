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
