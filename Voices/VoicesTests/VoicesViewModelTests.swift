import Observation
import Testing
@testable import Voices

struct FakeRecordingService: RecordingService {
    let count: Int

    func audioChunks() -> AsyncStream<AudioChunk> {
        let count = self.count
        return AsyncStream { continuation in
            Task {
                for i in 0..<count {
                    continuation.yield(AudioChunk(index: i))
                    await Task.yield()
                }
                continuation.finish()
            }
        }
    }
}

struct FakePlaybackService: PlaybackService {
    func play(_ chunks: [AudioChunk]) -> AsyncStream<Int> {
        AsyncStream { continuation in
            Task {
                for chunk in chunks {
                    continuation.yield(chunk.index)
                    await Task.yield()
                }
                continuation.finish()
            }
        }
    }
}

struct VoicesViewModelTests {
    @Test("Recording and listening are never both true", .timeLimit(.minutes(1)))
    func mutualExclusion() async {
        let producer = FakeRecordingService(count: 3)
        let playback = FakePlaybackService()
        let vm = VoicesViewModel(recordingService: producer, playbackService: playback)

        // Record some chunks so listening can start
        vm.toggleRecording()
        for await count in Observations({ vm.audioChunks.count }) {
            if count >= 3 { break }
        }
        vm.toggleRecording()
        #expect(vm.isRecording == false)

        // Start listening — has unplayed chunks
        vm.toggleListening()
        #expect(vm.isListening == true)
        #expect(vm.isRecording == false)

        // Toggle recording while listening — must stop listening first
        vm.toggleRecording()
        #expect(vm.isRecording == true)
        #expect(vm.isListening == false, "Listening must stop when recording starts")

        // Record more chunks, then stop, so listening can start again
        for await count in Observations({ vm.audioChunks.count }) {
            if count >= 3 { break }
        }
        vm.toggleRecording()

        // Start listening again
        vm.toggleListening()
        #expect(vm.isListening == true)
        #expect(vm.isRecording == false, "Recording must stop when listening starts")
    }

    @Test("Stop recording sets isRecording to false")
    func stopSetsFlag() {
        let vm = VoicesViewModel()
        vm.toggleRecording()
        vm.toggleRecording()
        #expect(vm.isRecording == false)
    }

    @Test("Listening plays back recorded chunks sequentially", .timeLimit(.minutes(1)))
    func listeningPlaysBackRecordedChunksSequentially() async {
        let producer = FakeRecordingService(count: 3)
        let playback = FakePlaybackService()
        let vm = VoicesViewModel(recordingService: producer, playbackService: playback)

        // Record 3 chunks
        vm.toggleRecording()
        for await count in Observations({ vm.audioChunks.count }) {
            if count >= 3 { break }
        }
        vm.toggleRecording()

        // Listen
        vm.toggleListening()
        #expect(vm.isListening == true)

        // Collect every playbackIndex change in order
        var indices: [Int] = []
        for await index in Observations({ vm.playbackIndex }) {
            indices.append(index)
            if index >= 2 { break }
        }

        // Wait for isListening to turn false
        for await listening in Observations({ vm.isListening }) {
            if !listening { break }
        }

        #expect(indices == [0, 1, 2], "Chunks must play sequentially, no skip")
        #expect(vm.isListening == false, "Must auto-stop after last chunk")
    }

    @Test("Listen does nothing when no chunks recorded")
    func listenNoOpWhenEmpty() {
        let vm = VoicesViewModel()

        let indexBefore = vm.playbackIndex
        vm.toggleListening()

        #expect(vm.isListening == false, "Should not start listening with nothing recorded")
        #expect(vm.playbackIndex == indexBefore, "playbackIndex should not move")
    }

    @Test("Resume listening continues from where it stopped", .timeLimit(.minutes(1)))
    func resumeContinuesFromCurrentIndex() async {
        let producer = FakeRecordingService(count: 5)
        let playback = FakePlaybackService()
        let vm = VoicesViewModel(recordingService: producer, playbackService: playback)

        // Record 5 chunks
        vm.toggleRecording()
        for await count in Observations({ vm.audioChunks.count }) {
            if count >= 5 { break }
        }
        vm.toggleRecording()

        // Start listening
        vm.toggleListening()

        // Wait until playbackIndex reaches 2
        for await index in Observations({ vm.playbackIndex }) {
            if index >= 2 { break }
        }

        // Stop mid-playback
        vm.toggleListening()
        let stoppedAt = vm.playbackIndex

        // Resume — should not reset playbackIndex
        vm.toggleListening()
        #expect(vm.playbackIndex == stoppedAt, "playbackIndex should not reset on resume")

        // Wait for playback to finish
        for await listening in Observations({ vm.isListening }) {
            if !listening { break }
        }

        #expect(vm.playbackIndex == 4, "Should play through to the end")
        #expect(vm.isListening == false)
    }

    @Test("Listen does nothing when everything already played", .timeLimit(.minutes(1)))
    func listenNoOpWhenFullyPlayed() async {
        let producer = FakeRecordingService(count: 3)
        let playback = FakePlaybackService()
        let vm = VoicesViewModel(recordingService: producer, playbackService: playback)

        // Record 3 chunks
        vm.toggleRecording()
        for await count in Observations({ vm.audioChunks.count }) {
            if count >= 3 { break }
        }
        vm.toggleRecording()

        // Play all chunks
        vm.toggleListening()
        for await listening in Observations({ vm.isListening }) {
            if !listening { break }
        }

        // Everything played — listen again should be no-op
        let indexBefore = vm.playbackIndex
        vm.toggleListening()

        #expect(vm.isListening == false, "Should not start listening when everything already played")
        #expect(vm.playbackIndex == indexBefore, "playbackIndex should not move")
    }

    @Test("hasUnplayedChunks reflects playback state")
    func hasUnplayedChunks() async {
        let producer = FakeRecordingService(count: 3)
        let playback = FakePlaybackService()
        let vm = VoicesViewModel(recordingService: producer, playbackService: playback)

        // No chunks recorded — nothing to play
        #expect(vm.hasUnplayedChunks == false)

        // Record 3 chunks
        vm.toggleRecording()
        for await count in Observations({ vm.audioChunks.count }) {
            if count >= 3 { break }
        }
        vm.toggleRecording()

        // Chunks recorded but not yet played — something to play
        #expect(vm.hasUnplayedChunks == true)

        // Play all chunks
        vm.toggleListening()
        for await listening in Observations({ vm.isListening }) {
            if !listening { break }
        }

        // Everything played — nothing left to play
        #expect(vm.hasUnplayedChunks == false)
    }

    @Test("Stop recording cancels chunk production", .timeLimit(.minutes(1)))
    func stopCancelsProduction() async {
        let producer = FakeRecordingService(count: 1000)
        let vm = VoicesViewModel(recordingService: producer)

        vm.toggleRecording()

        // Wait for at least one chunk — reactive, not polling
        for await count in Observations({ vm.audioChunks.count }) {
            if count >= 1 { break }
        }

        vm.toggleRecording()  // stop
        let countAfterStop = vm.audioChunks.count

        // Wait to see if any more chunks sneak through
        try? await Task.sleep(for: .milliseconds(50))

        #expect(vm.audioChunks.count == countAfterStop, "No new chunks should arrive after stop")
        #expect(countAfterStop < 1000, "Stream should have been cancelled before completing")
    }

    // MARK: - Multiple recordings (pending)

    @Test("Recording twice creates two separate recordings", .timeLimit(.minutes(1)))
    func recordingTwiceCreatesTwoRecordings() async {
        let producer = FakeRecordingService(count: 3)
        let vm = VoicesViewModel(recordingService: producer)

        // First recording
        vm.toggleRecording()
        for await count in Observations({ vm.audioChunks.count }) {
            if count >= 3 { break }
        }
        vm.toggleRecording()

        // Second recording
        vm.toggleRecording()
        for await count in Observations({ vm.audioChunks.count }) {
            if count >= 3 { break }
        }
        vm.toggleRecording()

        #expect(vm.recordings.count == 2, "Should have two recordings")
        #expect(vm.recordings[0].count == 3, "First recording should have 3 chunks")
        #expect(vm.recordings[1].count == 3, "Second recording should have 3 chunks")
    }

    // TEST: Playback plays all recordings sequentially
    // BEHAVIOR: after two recordings, pressing listen plays first then second without pause
    // FAIL IF: only one recording plays, or playback order is wrong
}
