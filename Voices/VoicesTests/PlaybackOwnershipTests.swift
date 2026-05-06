import Foundation
import Observation
import Testing
@testable import Voices

@MainActor
struct PlaybackOwnershipTests {

    /// Own-message rule, end to end through the playback path:
    /// VoicesViewModel.toggleListening → DemoPlaybackService → InMemoryDatabase.
    /// When the viewer is the recording's author, the chunk must stay
    /// unlistened. The assertion waits for the playback task to finish
    /// (`isListening` flips false) before reading the chunk's state —
    /// the violation today is async (consumePlayback's loop body), so
    /// a synchronous read would pass vacuously before the Task runs.
    @Test("Listening to my own recording through the VM leaves the chunk unlistened",
          .timeLimit(.minutes(1)))
    func ownListenThroughVMLeavesOwnChunkUnlistened() async {
        let me = UUID()
        let db = InMemoryDatabase()
        db.addRecording(Recording(
            id: UUID(),
            author: me,
            audioChunks: [AudioChunk(index: 0)]
        ))

        let vm = VoicesViewModel(
            recordingService: DemoRecordingService(database: db),
            playbackService: DemoPlaybackService(database: db, viewer: me),
            database: db,
            viewer: me
        )

        vm.toggleListening()
        for await listening in Observations({ vm.isListening }) {
            if !listening { break }
        }

        #expect(db.recordings.first?.audioChunks.first?.listened == false)
    }

    /// Read-side viewer-relative rule: my own unlistened chunks must
    /// not count toward `hasUnplayedChunks`. Pure synchronous read of
    /// a derived property — no playback, no async wait. Today's
    /// author-blind `recordings.flatMap(\.audioChunks).contains { !$0.listened }`
    /// returns true for an own-only DB, violating the rule.
    @Test("hasUnplayedChunks ignores my own recordings")
    func hasUnplayedChunksIgnoresOwnRecordings() {
        let me = UUID()
        let db = InMemoryDatabase()
        db.addRecording(Recording(
            id: UUID(),
            author: me,
            audioChunks: [AudioChunk(index: 0)]
        ))

        let vm = VoicesViewModel(
            recordingService: DemoRecordingService(database: db),
            playbackService: DemoPlaybackService(database: db, viewer: me),
            database: db,
            viewer: me
        )

        #expect(vm.hasUnplayedChunks == false)
    }

    /// Action-side viewer-relative rule: when an own recording sits in
    /// front of a foreign recording, pressing play must walk only the
    /// foreign chunks. The own recording's chunks must never appear in
    /// `playedChunks`. After completion, `hasUnplayedChunks` must flip
    /// to false because every foreign chunk is now listened. Red today
    /// because `DemoPlaybackService.resumePoint(in:)` is author-blind
    /// and starts at the own recording's chunk 0.
    @Test("Play skips an own recording and consumes only foreign chunks",
          .timeLimit(.minutes(1)))
    func playSkipsOwnRecordingAndConsumesOnlyForeignChunks() async {
        let me = UUID()
        let other = UUID()
        let db = InMemoryDatabase()
        let ownRec = Recording(
            id: UUID(),
            author: me,
            audioChunks: [AudioChunk(index: 0), AudioChunk(index: 1), AudioChunk(index: 2)]
        )
        let foreignRec = Recording(
            id: UUID(),
            author: other,
            audioChunks: [AudioChunk(index: 0), AudioChunk(index: 1), AudioChunk(index: 2)]
        )
        db.addRecording(ownRec)
        db.addRecording(foreignRec)

        let playback = DemoPlaybackService(database: db, viewer: me)
        let vm = VoicesViewModel(
            recordingService: DemoRecordingService(database: db),
            playbackService: playback,
            database: db,
            viewer: me
        )

        vm.toggleListening()
        for await listening in Observations({ vm.isListening }) {
            if !listening { break }
        }

        let expectedForeignOnly = [
            PlaybackPosition(recordingID: foreignRec.id, chunkIndex: 0),
            PlaybackPosition(recordingID: foreignRec.id, chunkIndex: 1),
            PlaybackPosition(recordingID: foreignRec.id, chunkIndex: 2),
        ]
        #expect(playback.playedChunks == expectedForeignOnly)
        #expect(vm.hasUnplayedChunks == false)
    }

    /// Continuity: chunks appended into a foreign recording during a
    /// live listening session must be consumed in that same session.
    /// Explicit 10 ms cadence so playback is genuinely in flight when
    /// the test injects the new chunks; the gate `playedChunks.count
    /// >= 1` proves the session is alive before the append happens.
    @Test("Playback continues into chunks appended during the same session",
          .timeLimit(.minutes(1)))
    func playbackContinuesIntoChunksAppendedDuringSameSession() async throws {
        let me = UUID()
        let other = UUID()
        let db = InMemoryDatabase()
        let rid = UUID()
        db.addRecording(Recording(
            id: rid,
            author: other,
            audioChunks: (0..<5).map { AudioChunk(index: $0) }
        ))

        let playback = DemoPlaybackService(database: db, viewer: me, delay: .milliseconds(10))
        let vm = VoicesViewModel(
            recordingService: DemoRecordingService(database: db),
            playbackService: playback,
            database: db,
            viewer: me
        )

        vm.toggleListening()

        // Confirm the session is underway before mutating the database.
        for await count in Observations({ playback.playedChunks.count }) {
            if count >= 1 { break }
        }

        // Inject three new chunks into the same recording, mid-session.
        db.appendChunk(AudioChunk(index: 5), to: rid)
        db.appendChunk(AudioChunk(index: 6), to: rid)
        db.appendChunk(AudioChunk(index: 7), to: rid)

        // Wait for playback to quiesce on its own.
        for await listening in Observations({ vm.isListening }) {
            if !listening { break }
        }

        let played = playback.playedChunks
        #expect(played.contains(PlaybackPosition(recordingID: rid, chunkIndex: 5)))
        #expect(played.contains(PlaybackPosition(recordingID: rid, chunkIndex: 6)))
        #expect(played.contains(PlaybackPosition(recordingID: rid, chunkIndex: 7)))
    }
}
