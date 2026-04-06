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
        // Sync VM state when store's listen loop finishes naturally
        Task {
            while store.isListening {
                try? await Task.sleep(for: .milliseconds(50))
            }
            if isListening {
                isListening = false
                log("Listening finished")
            }
        }
    }

    private func stopListening() {
        store.stopListening()
        isListening = false
        log("Listening stopped")
    }

    func scrubTo(_ index: Int) {
        guard !isRecording && !isListening else { return }
        store.scrubTo(index)
    }

    // MARK: - Self-test (drives real VM, visible in UI)

    #if DEBUG
    func selfTest() async {
        log("TEST: pressing record...")
        toggleRecording()

        // Record for 5 seconds (~50 chunks) — bars extend past screen center
        try? await Task.sleep(for: .seconds(5))
        let chunks = store.allChunks.count
        if chunks > 0 {
            log("TEST PASS: recording produced \(chunks) chunks (visible as gray bars)")
        } else {
            logError("TEST FAIL: recording produced 0 chunks")
        }

        // Try to scrub during recording — should be rejected
        let preRecordIdx = store.activeIndex
        scrubTo(0)
        if store.activeIndex == preRecordIdx {
            log("TEST PASS: scrub rejected during recording — activeIndex stayed at \(String(describing: store.activeIndex))")
        } else {
            logError("TEST FAIL: scrub moved activeIndex from \(String(describing: preRecordIdx)) to \(String(describing: store.activeIndex)) during recording — should be locked")
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

        // Press listen — bars should turn blue (.listened) and center should track
        log("TEST: pressing listen...")
        toggleListening()
        try? await Task.sleep(for: .milliseconds(500))

        // Try to scrub during listening — should be rejected
        let preListenIdx = store.activeIndex
        scrubTo(0)
        if store.activeIndex == preListenIdx {
            log("TEST PASS: scrub rejected during listening — activeIndex stayed at \(String(describing: store.activeIndex))")
        } else {
            logError("TEST FAIL: scrub moved activeIndex from \(String(describing: preListenIdx)) to \(String(describing: store.activeIndex)) during listening — should be locked")
        }

        // During listening, activeIndex should track the currently-listened chunk
        // Listening walks from chunk 0 forward at 100ms each. After 500ms, ~5 listened.
        // activeIndex should be near that position, NOT stuck at last recording index.
        let listenedSoFar = store.allChunks.filter { $0.status == .listened }.count
        let expectedIdx = max(0, listenedSoFar - 1)  // 0-indexed last listened chunk
        if let idx = store.activeIndex, abs(idx - expectedIdx) <= 1 {
            log("TEST PASS: activeIndex=\(idx) tracks listen position (expected ~\(expectedIdx)) — strip centered")
        } else {
            logError("TEST FAIL: activeIndex=\(String(describing: store.activeIndex)) should be ~\(expectedIdx) (listened \(listenedSoFar) chunks) — strip not centered during listening")
        }

        try? await Task.sleep(for: .seconds(8))
        let listened = store.allChunks.filter { $0.status == .listened }.count
        if listened > 0 {
            log("TEST PASS: \(listened)/\(chunks) chunks listened (bars turned blue)")
        } else {
            logError("TEST FAIL: 0/\(chunks) chunks listened — bars stayed purple, listening not implemented")
        }

        // After all listened, listen button should turn purple (nothing left)
        if !store.hasListenable {
            log("TEST PASS: hasListenable is false — listen button should be purple")
        } else {
            logError("TEST FAIL: hasListenable is still true after all chunks listened — button stays blue")
        }

        // Button icon should be pause when nothing to play
        let icon = (isListening || !store.hasListenable) ? "pause.fill" : "play.fill"
        if icon == "pause.fill" {
            log("TEST PASS: button shows pause.fill when nothing left to play")
        } else {
            logError("TEST FAIL: button shows \(icon) but should show pause.fill — nothing left to play")
        }

        // Button color: blue = something to listen to, purple = nothing new (allHeard or empty)
        let tint: String = store.hasListenable ? "blue" : "purple"
        if tint == "purple" && store.allHeard {
            log("TEST PASS: button is purple — allHeard=true, nothing new to listen to")
        } else if tint == "purple" && !store.allHeard {
            log("TEST PASS: button is purple — nothing listenable yet")
        } else {
            logError("TEST FAIL: button is \(tint) but expected purple after all listened")
        }

        // allHeard should be true — we just listened to everything
        if store.allHeard {
            log("TEST PASS: allHeard=true before scrub — everything heard once")
        } else {
            logError("TEST FAIL: allHeard=false before scrub — should be true")
        }

        // Scrub to chunk 10 — should move activeIndex and reset chunks after 10 to .uploaded
        log("TEST: scrubbing to chunk 10...")
        scrubTo(10)
        if store.activeIndex == 10 {
            log("TEST PASS: activeIndex moved to 10 after scrub")
        } else {
            logError("TEST FAIL: activeIndex=\(String(describing: store.activeIndex)) should be 10 after scrub")
        }

        // allHeard should STILL be true after scrub — we heard everything once, scrub is just visual
        if store.allHeard {
            log("TEST PASS: allHeard=true after scrub — persistent database remembers")
        } else {
            logError("TEST FAIL: allHeard=false after scrub — scrub destroyed persistent listened state, need database")
        }

        // After scrub to 10: chunks 0-10 = .listened (blue), chunks 11+ = .uploaded (purple)
        let listenedAfterScrub = store.allChunks.prefix(11).filter { $0.status == .listened }.count
        let uploadedAfterScrub = store.allChunks.dropFirst(11).filter { $0.status == .uploaded }.count
        let expectedUploaded = chunks - 11
        if listenedAfterScrub == 11 && uploadedAfterScrub == expectedUploaded {
            log("TEST PASS: scrub split — \(listenedAfterScrub) listened (blue), \(uploadedAfterScrub) uploaded (purple)")
        } else {
            logError("TEST FAIL: scrub split wrong — listened 0-10: \(listenedAfterScrub)/11, uploaded 11+: \(uploadedAfterScrub)/\(expectedUploaded)")
        }

        // After scrub: hasListenable=true (chunks 11+ are .uploaded) but allHeard=true (database).
        // Button should be purple because this is a re-listen, not fresh content.
        let scrubTint: String = store.hasListenable ? "blue" : "purple"
        if scrubTint == "purple" {
            log("TEST PASS: button is purple after scrub — allHeard, re-listen only")
        } else {
            logError("TEST FAIL: button is \(scrubTint) after scrub — should be purple because allHeard=\(store.allHeard), this is a re-listen")
        }

        // Press listen after scrub — should replay from chunk 11, centered there
        log("TEST: pressing listen after scrub to 10...")
        toggleListening()
        try? await Task.sleep(for: .milliseconds(500))

        // activeIndex should be near 11 (first .uploaded), not 0 or 10
        let replayIdx = store.activeIndex
        if let idx = replayIdx, idx >= 11 && idx <= 15 {
            log("TEST PASS: replay starts at activeIndex=\(idx) (near scrub point 11) — strip centered correctly")
        } else {
            logError("TEST FAIL: replay activeIndex=\(String(describing: replayIdx)) should be near 11 after scrub to 10 — strip not centered on replay start")
        }

        // Only chunks 11+ should be replaying — chunks 0-10 should still be .listened
        let firstElevenStatus = store.allChunks.prefix(11).allSatisfy { $0.status == .listened }
        if firstElevenStatus {
            log("TEST PASS: chunks 0-10 stayed .listened during replay (not re-replayed)")
        } else {
            logError("TEST FAIL: chunks 0-10 were modified during replay — should stay .listened")
        }

        // Wait for full replay
        try? await Task.sleep(for: .seconds(6))
        let relistened = store.allChunks.filter { $0.status == .listened }.count
        if relistened == chunks {
            log("TEST PASS: all \(relistened) chunks listened after scrub+replay")
        } else {
            logError("TEST FAIL: only \(relistened)/\(chunks) chunks listened after scrub+replay")
        }
    }
    #endif
}
