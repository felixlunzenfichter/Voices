import Foundation
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

@Observable
final class FakeDatabase: Database {
    var recordings: [Recording] = []

    func addRecording(_ recording: Recording) {
        recordings.append(recording)
    }

    func appendChunk(_ chunk: AudioChunk, to recordingID: UUID) {
        guard let index = recordings.firstIndex(where: { $0.id == recordingID }) else { return }
        recordings[index].audioChunks.append(chunk)
    }

    static func withOneRecording() -> FakeDatabase {
        let db = FakeDatabase()
        db.addRecording(Recording(audioChunks: [AudioChunk(index: 0)]))
        return db
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

    @Test("ViewModel reflects store changes")
    func viewModelReflectsStoreChanges() {
        let db = FakeDatabase()
        let vm = VoicesViewModel(database: db)

        #expect(vm.recordings.isEmpty)

        db.addRecording(Recording(audioChunks: [AudioChunk(index: 0)]))

        #expect(vm.recordings.count == 1)
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

    @Test("Recorded chunks appear in database", .timeLimit(.minutes(1)))
    func recordedChunksAppearInDatabase() async throws {
        let producer = FakeRecordingService(count: 3)
        let db = FakeDatabase()
        let vm = VoicesViewModel(recordingService: producer, database: db)

        vm.toggleRecording()

        for await count in Observations({ vm.recordings.last?.audioChunks.count ?? 0 }) {
            if count >= 3 { break }
        }

        vm.toggleRecording()

        let recording = try #require(db.recordings.last)
        #expect(recording.audioChunks.count == 3)
    }
}
