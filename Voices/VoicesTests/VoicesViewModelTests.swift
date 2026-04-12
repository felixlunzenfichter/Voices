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

    func removeRecording(_ recordingID: UUID) {
        recordings.removeAll { $0.id == recordingID }
    }

    static func withRecording(chunkCount: Int) -> FakeDatabase {
        let db = FakeDatabase()
        let chunks = (0..<chunkCount).map { AudioChunk(index: $0) }
        db.addRecording(Recording(audioChunks: chunks))
        return db
    }

    static func withOneRecording() -> FakeDatabase {
        withRecording(chunkCount: 1)
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

    @Test("Recording twice creates two distinct recordings", .timeLimit(.minutes(1)))
    func recordingTwiceCreatesTwoDistinctRecordings() async throws {
        let producer = FakeRecordingService(count: 2)
        let db = FakeDatabase()
        let vm = VoicesViewModel(recordingService: producer, database: db)

        vm.toggleRecording()
        for await count in Observations({ vm.recordings.last?.audioChunks.count ?? 0 }) {
            if count >= 2 { break }
        }
        vm.toggleRecording()

        vm.toggleRecording()
        for await count in Observations({ vm.recordings.last?.audioChunks.count ?? 0 }) {
            if count >= 2 { break }
        }
        vm.toggleRecording()

        #expect(vm.recordings.count == 2)

        let first = try #require(vm.recordings.first)
        let second = try #require(vm.recordings.last)
        #expect(first.id != second.id, "Each recording should have a unique ID")
        #expect(first.audioChunks.count == 2)
        #expect(second.audioChunks.count == 2)
    }

    @Test("Listening auto-stops after last chunk", .timeLimit(.minutes(1)))
    func listeningAutoStopsAfterLastChunk() async {
        let playback = FakePlaybackService()
        let db = FakeDatabase.withOneRecording()
        let vm = VoicesViewModel(playbackService: playback, database: db)

        vm.toggleListening()
        #expect(vm.isListening == true)

        for await listening in Observations({ vm.isListening }) {
            if !listening { break }
        }

        #expect(vm.isListening == false)
    }

    @Test("Listen does nothing when everything already played", .timeLimit(.minutes(1)))
    func listenDoesNothingWhenEverythingAlreadyPlayed() async {
        let playback = FakePlaybackService()
        let db = FakeDatabase.withOneRecording()
        let vm = VoicesViewModel(playbackService: playback, database: db)

        // Play everything
        vm.toggleListening()
        for await listening in Observations({ vm.isListening }) {
            if !listening { break }
        }

        // Try again — should be a no-op
        #expect(vm.isListening == false)
        vm.toggleListening()
        #expect(vm.isListening == false)
    }

    @Test("Playback position tracks recording and chunk", .timeLimit(.minutes(1)))
    func playbackPositionTracksRecordingAndChunk() async {
        let playback = FakePlaybackService()
        let db = FakeDatabase.withOneRecording()
        let vm = VoicesViewModel(playbackService: playback, database: db)

        #expect(vm.playbackPosition == nil)

        vm.toggleListening()

        for await position in Observations({ vm.playbackPosition }) {
            if position != nil { break }
        }

        let expectedID = db.recordings.first!.id
        #expect(vm.playbackPosition == PlaybackPosition(recordingID: expectedID, chunkIndex: 0))
    }

    @Test("Listening plays back chunks sequentially", .timeLimit(.minutes(1)))
    func listeningPlaysBackChunksSequentially() async {
        let playback = FakePlaybackService()
        let db = FakeDatabase.withRecording(chunkCount: 3)
        let vm = VoicesViewModel(playbackService: playback, database: db)

        vm.toggleListening()

        var positions: [PlaybackPosition] = []
        for await position in Observations({ vm.playbackPosition }) {
            guard let position else { continue }
            positions.append(position)
            if positions.count >= 3 { break }
        }

        let expectedID = db.recordings.first!.id
        #expect(positions == [
            PlaybackPosition(recordingID: expectedID, chunkIndex: 0),
            PlaybackPosition(recordingID: expectedID, chunkIndex: 1),
            PlaybackPosition(recordingID: expectedID, chunkIndex: 2),
        ])
    }

    @Test("Resume listening continues from where it stopped", .timeLimit(.minutes(1)))
    func resumeListeningContinuesFromWhereItStopped() async {
        let playback = FakePlaybackService()
        let db = FakeDatabase.withRecording(chunkCount: 6)
        let vm = VoicesViewModel(playbackService: playback, database: db)
        let expectedID = db.recordings.first!.id

        // Phase 1: play first three
        vm.toggleListening()
        var phase1: [PlaybackPosition] = []
        for await position in Observations({ vm.playbackPosition }) {
            guard let position else { continue }
            phase1.append(position)
            if phase1.count >= 3 { break }
        }
        vm.toggleListening()

        // Phase 2: resume, play next three
        vm.toggleListening()
        var phase2: [PlaybackPosition] = []
        for await position in Observations({ vm.playbackPosition }) {
            guard let position else { continue }
            if position.chunkIndex > 2 {
                phase2.append(position)
            }
            if phase2.count >= 3 { break }
        }

        #expect(phase1 == [
            PlaybackPosition(recordingID: expectedID, chunkIndex: 0),
            PlaybackPosition(recordingID: expectedID, chunkIndex: 1),
            PlaybackPosition(recordingID: expectedID, chunkIndex: 2),
        ])
        #expect(phase2 == [
            PlaybackPosition(recordingID: expectedID, chunkIndex: 3),
            PlaybackPosition(recordingID: expectedID, chunkIndex: 4),
            PlaybackPosition(recordingID: expectedID, chunkIndex: 5),
        ])
    }

    @Test("Playback crosses recording boundary", .timeLimit(.minutes(1)))
    func playbackCrossesRecordingBoundary() async {
        let playback = FakePlaybackService()
        let db = FakeDatabase()
        let r1 = Recording(audioChunks: [AudioChunk(index: 0), AudioChunk(index: 1)])
        let r2 = Recording(audioChunks: [AudioChunk(index: 0), AudioChunk(index: 1)])
        db.addRecording(r1)
        db.addRecording(r2)
        let vm = VoicesViewModel(playbackService: playback, database: db)

        vm.toggleListening()

        var positions: [PlaybackPosition] = []
        for await position in Observations({ vm.playbackPosition }) {
            guard let position else { continue }
            positions.append(position)
            if positions.count >= 4 { break }
        }

        #expect(positions == [
            PlaybackPosition(recordingID: r1.id, chunkIndex: 0),
            PlaybackPosition(recordingID: r1.id, chunkIndex: 1),
            PlaybackPosition(recordingID: r2.id, chunkIndex: 0),
            PlaybackPosition(recordingID: r2.id, chunkIndex: 1),
        ])
    }

    @Test("Record after full playback plays only new recording", .timeLimit(.minutes(1)))
    func recordAfterFullPlaybackPlaysOnlyNewRecording() async {
        let producer = FakeRecordingService(count: 2)
        let playback = FakePlaybackService()
        let db = FakeDatabase()
        let vm = VoicesViewModel(recordingService: producer, playbackService: playback, database: db)

        // Record first
        vm.toggleRecording()
        for await count in Observations({ vm.recordings.last?.audioChunks.count ?? 0 }) {
            if count >= 2 { break }
        }
        vm.toggleRecording()

        // Play all
        vm.toggleListening()
        for await listening in Observations({ vm.isListening }) {
            if !listening { break }
        }

        // Record again
        vm.toggleRecording()
        for await count in Observations({ vm.recordings.last?.audioChunks.count ?? 0 }) {
            if count >= 2 { break }
        }
        vm.toggleRecording()
        let secondID = vm.recordings.last!.id

        // Play again
        vm.toggleListening()
        var positions: [PlaybackPosition] = []
        for await position in Observations({ vm.playbackPosition }) {
            guard let position else { continue }
            positions.append(position)
            if positions.count >= 2 { break }
        }

        #expect(positions == [
            PlaybackPosition(recordingID: secondID, chunkIndex: 0),
            PlaybackPosition(recordingID: secondID, chunkIndex: 1),
        ])
    }

    @Test("Immediate stop does not persist empty recording")
    func immediateStopDoesNotPersistEmptyRecording() {
        let vm = VoicesViewModel()

        vm.toggleRecording()
        vm.toggleRecording()

        #expect(vm.recordings.isEmpty, "No empty recording should remain in the database")
    }
}
