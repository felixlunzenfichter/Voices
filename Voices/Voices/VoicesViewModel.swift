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
        log("Recording started")
    }

    private func stopRecording() {
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
