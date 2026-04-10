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

struct FakeDatabase: Database {
    var recordings: [[AudioChunk]]

    static func withOneRecording() -> FakeDatabase {
        FakeDatabase(recordings: [[AudioChunk(index: 0)]])
    }
}

struct VoicesViewModelTests {
    @Test("Toggle recording toggles isRecording")
    func toggleRecordingTogglesState() {
        let vm = VoicesViewModel()

        vm.toggleRecording()
        #expect(vm.isRecording == true)

        vm.toggleRecording()
        #expect(vm.isRecording == false)
    }

    @Test("Listen does nothing when nothing recorded")
    func listenDoesNothingWhenNothingRecorded() {
        let vm = VoicesViewModel()

        #expect(vm.isListening == false)
        vm.toggleListening()
        #expect(vm.isListening == false)
    }

    @Test("Toggle listening toggles isListening")
    func toggleListeningTogglesState() {
        let vm = VoicesViewModel(database: FakeDatabase.withOneRecording())

        #expect(vm.isListening == false)
        vm.toggleListening()
        #expect(vm.isListening == true)

        vm.toggleListening()
        #expect(vm.isListening == false)
    }

    @Test("State transitions: record, listen, record")
    func stateTransitions() {
        let db = FakeDatabase.withOneRecording()
        let vm = VoicesViewModel(database: db)

        // Start recording
        vm.toggleRecording()
        #expect(vm.isRecording == true)
        #expect(vm.isListening == false)

        // Start listening — stops recording
        vm.toggleListening()
        #expect(vm.isListening == true)
        #expect(vm.isRecording == false)

        // Start recording — stops listening
        vm.toggleRecording()
        #expect(vm.isRecording == true)
        #expect(vm.isListening == false)
    }

    @Test("Stop recording stops chunk production", .timeLimit(.minutes(1)))
    func stopRecordingStopsChunkProduction() async throws {
        let producer = FakeRecordingService(count: 1000)
        let vm = VoicesViewModel(recordingService: producer)

        vm.toggleRecording()

        for await count in Observations({ vm.recordings.last?.audioChunks.count ?? 0 }) {
            if count >= 1 { break }
        }

        vm.toggleRecording()
        let countAfterStop = vm.recordings.last?.audioChunks.count ?? 0

        try await Task.sleep(for: .milliseconds(50))

        let countAfterWait = vm.recordings.last?.audioChunks.count ?? 0
        #expect(countAfterWait == countAfterStop, "No chunks should arrive after stop")
        #expect(countAfterStop > 0, "Should have recorded some chunks")
        #expect(countAfterStop < 1000, "Should have stopped before finishing")
    }
}
