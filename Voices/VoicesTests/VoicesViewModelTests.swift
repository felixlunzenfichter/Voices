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

struct VoicesViewModelTests {
    @Test("Recording and listening are never both true")
    func mutualExclusion() {
        let vm = VoicesViewModel()

        vm.toggleRecording()
        #expect(vm.isRecording == true)
        #expect(vm.isListening == false)

        // Toggle listening while recording — must stop recording first
        vm.toggleListening()
        #expect(vm.isListening == true)
        #expect(vm.isRecording == false, "Recording must stop when listening starts")

        // Toggle recording while listening — must stop listening first
        vm.toggleRecording()
        #expect(vm.isRecording == true)
        #expect(vm.isListening == false, "Listening must stop when recording starts")
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
}
