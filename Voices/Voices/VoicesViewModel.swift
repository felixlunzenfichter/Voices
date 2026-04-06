import SwiftUI

@Observable @MainActor
final class VoicesViewModel {
    let store = ChunkStore()
    private var chunkTimer: Task<Void, Never>?

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
        store.startRecording()
        chunkTimer = Task {
            while !Task.isCancelled {
                store.appendChunk()
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        log("Recording started")
    }

    private func stopRecording() {
        chunkTimer?.cancel()
        chunkTimer = nil
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
