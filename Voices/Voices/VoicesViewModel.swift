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
        store.startListening()
        log("Listening started")
    }

    private func stopListening() {
        store.stopListening()
        isListening = false
        log("Listening stopped")
    }

    // MARK: - Self-test (drives real VM, visible in UI)

    #if DEBUG
    func selfTest() async {
        log("TEST: pressing record...")
        toggleRecording()

        // Record for 1 second — bars appear on screen
        try? await Task.sleep(for: .seconds(1))
        let chunks = store.allChunks.count
        if chunks > 0 {
            log("TEST PASS: recording produced \(chunks) chunks (visible as gray bars)")
        } else {
            logError("TEST FAIL: recording produced 0 chunks")
        }

        log("TEST: pressing record again to stop...")
        toggleRecording()

        // Wait for uploads — bars should turn purple
        try? await Task.sleep(for: .seconds(2))
        let uploaded = store.allChunks.filter { $0.status == .uploaded }.count
        if uploaded > 0 {
            log("TEST PASS: \(uploaded)/\(chunks) chunks uploaded (bars turned purple)")
        } else {
            logError("TEST FAIL: 0/\(chunks) chunks uploaded — bars stayed gray")
        }

        // Press listen — bars should turn blue (.listened)
        log("TEST: pressing listen...")
        toggleListening()
        try? await Task.sleep(for: .seconds(2))
        let listened = store.allChunks.filter { $0.status == .listened }.count
        if listened > 0 {
            log("TEST PASS: \(listened)/\(chunks) chunks listened (bars turned blue)")
        } else {
            logError("TEST FAIL: 0/\(chunks) chunks listened — bars stayed purple, listening not implemented")
        }
    }
    #endif
}
