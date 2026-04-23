import Foundation
import Observation
import Testing
@testable import Voices

// MARK: - Test helpers

extension InMemoryDatabase {
    static func withRecording(chunkCount: Int) -> InMemoryDatabase {
        let db = InMemoryDatabase()
        let chunks = (0..<chunkCount).map { AudioChunk(index: $0) }
        db.addRecording(Recording(audioChunks: chunks))
        return db
    }

    static func withOneRecording() -> InMemoryDatabase {
        withRecording(chunkCount: 1)
    }
}

extension VoicesViewModel {
    @MainActor
    static func fixture(
        db: InMemoryDatabase = InMemoryDatabase(),
        recordingCount: Int = .max
    ) -> VoicesViewModel {
        let rec = DemoRecordingService(database: db, count: recordingCount)
        let play = DemoPlaybackService(database: db)
        return VoicesViewModel(recordingService: rec, playbackService: play, database: db)
    }

    @MainActor
    static func fixtureWithDatabase(
        db: InMemoryDatabase = InMemoryDatabase(),
        recordingCount: Int = .max
    ) -> (vm: VoicesViewModel, db: InMemoryDatabase) {
        let vm = fixture(db: db, recordingCount: recordingCount)
        return (vm, db)
    }
}

struct VoicesViewModelTests {
    @Test("Toggle recording toggles isRecording")
    func toggleRecordingTogglesState() {
        let vm = VoicesViewModel.fixture()

        vm.toggleRecording()
        #expect(vm.isRecording == true)

        vm.toggleRecording()
        #expect(vm.isRecording == false)
    }

    @Test("Listen does nothing when nothing recorded")
    func listenDoesNothingWhenNothingRecorded() {
        let vm = VoicesViewModel.fixture()

        #expect(vm.isListening == false)
        vm.toggleListening()
        #expect(vm.isListening == false)
    }

    @Test("Toggle listening toggles isListening")
    func toggleListeningTogglesState() {
        let vm = VoicesViewModel.fixture(db: InMemoryDatabase.withOneRecording())

        #expect(vm.isListening == false)
        vm.toggleListening()
        #expect(vm.isListening == true)

        vm.toggleListening()
        #expect(vm.isListening == false)
    }

    @Test("State transitions: record, listen, record")
    func stateTransitions() {
        let vm = VoicesViewModel.fixture(db: InMemoryDatabase.withOneRecording())

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
        let (vm, db) = VoicesViewModel.fixtureWithDatabase()

        #expect(vm.recordings.isEmpty)

        db.addRecording(Recording(audioChunks: [AudioChunk(index: 0)]))

        #expect(vm.recordings.count == 1)
    }

    @Test("Stop recording stops chunk production", .timeLimit(.minutes(1)))
    func stopRecordingStopsChunkProduction() async throws {
        let vm = VoicesViewModel.fixture(recordingCount: 1000)

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
        let (vm, db) = VoicesViewModel.fixtureWithDatabase(recordingCount: 3)

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
        let vm = VoicesViewModel.fixture(recordingCount: 2)

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
        let vm = VoicesViewModel.fixture(db: InMemoryDatabase.withOneRecording())

        vm.toggleListening()
        #expect(vm.isListening == true)

        for await listening in Observations({ vm.isListening }) {
            if !listening { break }
        }

        #expect(vm.isListening == false)
    }

    @Test("Listen does nothing when everything already played", .timeLimit(.minutes(1)))
    func listenDoesNothingWhenEverythingAlreadyPlayed() async {
        let vm = VoicesViewModel.fixture(db: InMemoryDatabase.withOneRecording())

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
        let (vm, db) = VoicesViewModel.fixtureWithDatabase(db: InMemoryDatabase.withOneRecording())

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
        let (vm, db) = VoicesViewModel.fixtureWithDatabase(db: InMemoryDatabase.withRecording(chunkCount: 3))

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
        let (vm, db) = VoicesViewModel.fixtureWithDatabase(db: InMemoryDatabase.withRecording(chunkCount: 6))
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
        let db = InMemoryDatabase()
        let r1 = Recording(audioChunks: [AudioChunk(index: 0), AudioChunk(index: 1)])
        let r2 = Recording(audioChunks: [AudioChunk(index: 0), AudioChunk(index: 1)])
        db.addRecording(r1)
        db.addRecording(r2)
        let vm = VoicesViewModel.fixture(db: db)

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
        let vm = VoicesViewModel.fixture(recordingCount: 2)

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
        let vm = VoicesViewModel.fixture()

        vm.toggleRecording()
        vm.toggleRecording()

        #expect(vm.recordings.isEmpty, "No empty recording should remain in the database")
    }

    @Test("hasUnplayedChunks reflects playback state", .timeLimit(.minutes(1)))
    func hasUnplayedChunksReflectsPlaybackState() async {
        let vm = VoicesViewModel.fixture(recordingCount: 2)

        // Nothing recorded — nothing to play
        #expect(vm.hasUnplayedChunks == false)

        // After recording — something to play
        vm.toggleRecording()
        for await count in Observations({ vm.recordings.last?.audioChunks.count ?? 0 }) {
            if count >= 2 { break }
        }
        vm.toggleRecording()
        #expect(vm.hasUnplayedChunks == true)

        // After full playback — nothing to play
        vm.toggleListening()
        for await listening in Observations({ vm.isListening }) {
            if !listening { break }
        }
        #expect(vm.hasUnplayedChunks == false)

        // After recording again — something to play again
        vm.toggleRecording()
        for await count in Observations({ vm.recordings.last?.audioChunks.count ?? 0 }) {
            if count >= 2 { break }
        }
        vm.toggleRecording()
        #expect(vm.hasUnplayedChunks == true)
    }
}

// MARK: - Chunk-level listened state

struct ChunkListenedStateTests {

    @Test("New chunks have listened = false")
    func newChunksStartUnlistened() {
        let chunk = AudioChunk(index: 0)
        #expect(chunk.listened == false)
    }

    @Test("Chunks ahead of cursor remain not-listened during playback", .timeLimit(.minutes(1)))
    func chunksAheadNotListened() async {
        let (vm, db) = VoicesViewModel.fixtureWithDatabase(db: InMemoryDatabase.withRecording(chunkCount: 6))

        vm.toggleListening()
        for await pos in Observations({ vm.playbackPosition }) {
            if let p = pos, p.chunkIndex >= 2 { break }
        }
        vm.toggleListening()

        let chunks = db.recordings[0].audioChunks
        #expect(chunks[0...2].allSatisfy { $0.listened })
        #expect(chunks[3...5].allSatisfy { !$0.listened })
    }

    @Test("markListened is observable through ViewModel derived state")
    func markListenedObservableThroughViewModel() {
        let (vm, db) = VoicesViewModel.fixtureWithDatabase(db: InMemoryDatabase.withRecording(chunkCount: 3))
        let rid = db.recordings[0].id

        #expect(vm.hasUnplayedChunks == true)

        db.markListened(recordingID: rid, chunkIndex: 0)
        db.markListened(recordingID: rid, chunkIndex: 1)
        db.markListened(recordingID: rid, chunkIndex: 2)

        #expect(vm.hasUnplayedChunks == false)
    }
}

// MARK: - Seek

struct SeekTests {

    @Test("seekTo clamps to valid range")
    func seekToClampsToValidRange() {
        let (vm, db) = VoicesViewModel.fixtureWithDatabase(db: InMemoryDatabase.withRecording(chunkCount: 5))
        let rid = db.recordings[0].id

        vm.seekTo(-10)
        #expect(vm.playbackPosition == PlaybackPosition(recordingID: rid, chunkIndex: 0))

        vm.seekTo(99)
        #expect(vm.playbackPosition == nil, "Clamps to terminal, clears position")
        #expect(vm.scrubberIndex == 5)

        vm.seekTo(5)
        #expect(vm.playbackPosition == nil, "Terminal index clears position")

        vm.seekTo(4)
        #expect(vm.playbackPosition == PlaybackPosition(recordingID: rid, chunkIndex: 4))
    }

    @Test("seekTo does not mark chunks listened")
    func seekToDoesNotMarkListened() {
        let vm = VoicesViewModel.fixture(db: InMemoryDatabase.withRecording(chunkCount: 5))

        vm.seekTo(3)

        let allChunks = vm.recordings.flatMap(\.audioChunks)
        #expect(allChunks.allSatisfy { !$0.listened })
    }

    @Test("seekTo crosses message boundaries")
    func seekToCrossesMessageBoundaries() {
        let db = InMemoryDatabase()
        let r1 = Recording(audioChunks: [AudioChunk(index: 0), AudioChunk(index: 1), AudioChunk(index: 2)])
        let r2 = Recording(audioChunks: [AudioChunk(index: 0), AudioChunk(index: 1)])
        db.addRecording(r1)
        db.addRecording(r2)
        let vm = VoicesViewModel.fixture(db: db)

        vm.seekTo(4)
        #expect(vm.playbackPosition == PlaybackPosition(recordingID: r2.id, chunkIndex: 1))

        vm.seekTo(1)
        #expect(vm.playbackPosition == PlaybackPosition(recordingID: r1.id, chunkIndex: 1))
    }

    @Test("Listen after seekTo starts from seeked position", .timeLimit(.minutes(1)))
    func listenAfterSeekToStartsFromSeekedPosition() async {
        let vm = VoicesViewModel.fixture(db: InMemoryDatabase.withRecording(chunkCount: 10))

        vm.seekTo(5)
        vm.toggleListening()

        for await listening in Observations({ vm.isListening }) {
            if !listening { break }
        }

        // Chunks 0-4 unlistened, 5-9 listened
        #expect(vm.recordings[0].audioChunks[0...4].allSatisfy { !$0.listened })
        #expect(vm.recordings[0].audioChunks[5...9].allSatisfy { $0.listened })
    }

    @Test("Seek to listened chunk and listen starts from there", .timeLimit(.minutes(1)))
    func seekToListenedChunkAndListenStartsFromThere() async {
        let (vm, db) = VoicesViewModel.fixtureWithDatabase(db: InMemoryDatabase.withRecording(chunkCount: 10))
        let rid = db.recordings[0].id

        // Play all to completion
        vm.toggleListening()
        for await listening in Observations({ vm.isListening }) {
            if !listening { break }
        }

        // All listened. Seek back to chunk 7.
        #expect(vm.hasUnplayedChunks == false)
        vm.seekTo(7)
        #expect(vm.playbackPosition == PlaybackPosition(recordingID: rid, chunkIndex: 7))

        // Listen again — collect positions 7 through 9
        vm.toggleListening()
        var positions: [PlaybackPosition] = []
        for await pos in Observations({ vm.playbackPosition }) {
            guard let p = pos else { continue }
            positions.append(p)
            if positions.count >= 3 { break }
        }

        #expect(positions == [
            PlaybackPosition(recordingID: rid, chunkIndex: 7),
            PlaybackPosition(recordingID: rid, chunkIndex: 8),
            PlaybackPosition(recordingID: rid, chunkIndex: 9),
        ])
    }

    @Test("After natural completion, playbackPosition resets to first unlistened chunk", .timeLimit(.minutes(1)))
    func afterCompletionPositionResetsToFirstUnlistened() async {
        let (vm, db) = VoicesViewModel.fixtureWithDatabase(db: InMemoryDatabase.withRecording(chunkCount: 10))
        let rid = db.recordings[0].id

        // Seek to chunk 5, play to end (chunks 5-9 listened, 0-4 unlistened)
        vm.seekTo(5)
        vm.toggleListening()
        for await listening in Observations({ vm.isListening }) {
            if !listening { break }
        }

        // Position should be chunk 0 (first unlistened), not nil
        #expect(vm.playbackPosition == PlaybackPosition(recordingID: rid, chunkIndex: 0))
    }

    @Test("After full playback, cursor stays at last chunk", .timeLimit(.minutes(1)))
    func afterFullPlaybackCursorStaysAtLastChunk() async {
        let vm = VoicesViewModel.fixture(db: InMemoryDatabase.withRecording(chunkCount: 5))

        vm.toggleListening()
        for await listening in Observations({ vm.isListening }) {
            if !listening { break }
        }

        #expect(vm.playbackPosition == nil)
        #expect(vm.scrubberIndex == 5, "Terminal slot: totalChunkCount")
    }
}
