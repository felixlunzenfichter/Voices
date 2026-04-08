struct AudioChunk: Equatable {
    let index: Int
}

protocol RecordingService {
    func audioChunks() -> AsyncStream<AudioChunk>
}

struct SilentRecordingService: RecordingService {
    func audioChunks() -> AsyncStream<AudioChunk> {
        AsyncStream { $0.finish() }
    }
}

struct DemoRecordingService: RecordingService {
    func audioChunks() -> AsyncStream<AudioChunk> {
        AsyncStream { continuation in
            let task = Task {
                var index = 0
                while !Task.isCancelled {
                    continuation.yield(AudioChunk(index: index))
                    index += 1
                    try? await Task.sleep(for: .milliseconds(300))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
