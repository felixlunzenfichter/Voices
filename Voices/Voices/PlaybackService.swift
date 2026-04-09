protocol PlaybackService {
    func play(_ chunks: [AudioChunk]) -> AsyncStream<Int>
}

struct SilentPlaybackService: PlaybackService {
    func play(_ chunks: [AudioChunk]) -> AsyncStream<Int> {
        AsyncStream { $0.finish() }
    }
}
