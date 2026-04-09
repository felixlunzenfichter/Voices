protocol PlaybackService {
    func play(_ chunks: [AudioChunk]) -> AsyncStream<Int>
}

struct SilentPlaybackService: PlaybackService {
    func play(_ chunks: [AudioChunk]) -> AsyncStream<Int> {
        AsyncStream { $0.finish() }
    }
}

struct DemoPlaybackService: PlaybackService {
    func play(_ chunks: [AudioChunk]) -> AsyncStream<Int> {
        AsyncStream { continuation in
            let task = Task {
                for chunk in chunks {
                    continuation.yield(chunk.index)
                    try? await Task.sleep(for: .milliseconds(300))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
