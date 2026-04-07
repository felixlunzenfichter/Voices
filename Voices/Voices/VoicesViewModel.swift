import SwiftUI

@Observable @MainActor
final class VoicesViewModel {
    private(set) var isRecording = false {
        didSet {
            if isRecording && isListening {
                logError("INVARIANT: isRecording=\(isRecording) isListening=\(isListening) — both true simultaneously")
            }
        }
    }
    private(set) var isListening = false {
        didSet {
            if isRecording && isListening {
                logError("INVARIANT: isRecording=\(isRecording) isListening=\(isListening) — both true simultaneously")
            }
        }
    }
    private(set) var chunks: [Chunk] = []

    private let chunkProducer: any ChunkProducer
    private var recordingTask: Task<Void, Never>?

    init(chunkProducer: any ChunkProducer = SilentChunkProducer()) {
        self.chunkProducer = chunkProducer
    }

    func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    func toggleListening() {
        isListening ? stopListening() : startListening()
    }

    private func startRecording() {
        if isListening {
            withAnimation(.spring(duration: 1/φ, bounce: 1 - 1/φ)) {
                stopListening()
            }
        }
        isRecording = true
        chunks = []
        recordingTask = Task {
            for await chunk in chunkProducer.chunks() {
                guard !Task.isCancelled else { break }
                chunks.append(chunk)
            }
        }
        log("Recording started")
    }

    private func stopRecording() {
        recordingTask?.cancel()
        recordingTask = nil
        isRecording = false
        log("Recording stopped")
        sendNotification(title: "Recording", body: "Stopped")
    }

    private func startListening() {
        if isRecording {
            withAnimation(.spring(duration: 1/φ, bounce: 1 - 1/φ)) {
                stopRecording()
            }
        }
        isListening = true
        log("Listening started")
    }

    private func stopListening() {
        isListening = false
        log("Listening stopped")
    }
}
