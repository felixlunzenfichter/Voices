import SwiftUI

@Observable @MainActor
final class VoicesViewModel {
    private(set) var isRecording = false
    private(set) var isListening = false

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
        checkExclusion()
        log("Recording started")
    }

    private func stopRecording() {
        isRecording = false
        checkExclusion()
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
        checkExclusion()
        log("Listening started")
    }

    private func stopListening() {
        isListening = false
        checkExclusion()
        log("Listening stopped")
    }

    private func checkExclusion() {
        if isRecording && isListening {
            logError("INVARIANT: isRecording=\(isRecording) isListening=\(isListening) — both true simultaneously")
        }
    }
}
