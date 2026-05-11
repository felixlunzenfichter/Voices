import Foundation
import Testing
@testable import Voices

/// Test-only in-memory `Cloud` fake. Both PersistentDatabase instances
/// in the test share one of these to model the cross-device propagation
/// path. No network, no Mac server — that's a later commit.
@MainActor
private final class InMemoryCloud: Cloud {
    private var stored: [Recording] = []
    func get() async throws -> [Recording] { stored }
    func set(_ recordings: [Recording]) async throws { stored = recordings }
}

@MainActor
struct RealDatabaseTests {

    /// Two PersistentDatabase instances on one device with distinct
    /// `localFileURL`s, sharing one `Cloud`, observe a recording move
    /// through four states:
    ///
    ///   Stage 1 — A: isStoredLocally=true,  isStoredRemotely=false
    ///   Stage 2 — A: isStoredLocally=true,  isStoredRemotely=true
    ///   Stage 3 — B: isStoredLocally=false, isStoredRemotely=true
    ///   Stage 4 — B: isStoredLocally=true,  isStoredRemotely=true
    ///
    /// "A: local first, then remote; B: remote first, then local."
    /// B only learns about the recording when the test explicitly calls
    /// `pullFromRemote()` — there is no notification mechanism.
    @Test("Recording propagates A: local→remote, then B: remote→local")
    func recordingProgressesLocalThenRemoteOnA_RemoteThenLocalOnB() async throws {
        let urlA = FileManager.default.temporaryDirectory
            .appending(path: "scratch-A-\(UUID().uuidString).json")
        let urlB = FileManager.default.temporaryDirectory
            .appending(path: "scratch-B-\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: urlA)
            try? FileManager.default.removeItem(at: urlB)
        }

        let cloud = InMemoryCloud()
        let dbA = PersistentDatabase(localFileURL: urlA, cloud: cloud)
        let dbB = PersistentDatabase(localFileURL: urlB, cloud: cloud)

        let rec = Recording()

        // Stage 1: A creates locally.
        dbA.addRecording(rec)
        var s = try #require(dbA.stored.first { $0.recording.id == rec.id })
        #expect(s.isStoredLocally == true)
        #expect(s.isStoredRemotely == false)

        // Stage 2: A pushes to the cloud.
        try await dbA.pushToRemote()
        s = try #require(dbA.stored.first { $0.recording.id == rec.id })
        #expect(s.isStoredLocally == true)
        #expect(s.isStoredRemotely == true)

        // Stage 3: B pulls from the cloud (in-memory only, not yet on B's disk).
        try await dbB.pullFromRemote()
        s = try #require(dbB.stored.first { $0.recording.id == rec.id })
        #expect(s.isStoredRemotely == true)
        #expect(s.isStoredLocally == false)

        // Stage 4: B persists locally.
        try await dbB.persistToLocal()
        s = try #require(dbB.stored.first { $0.recording.id == rec.id })
        #expect(s.isStoredLocally == true)
        #expect(s.isStoredRemotely == true)
    }

    /// First red of the "marina sees mama's chunks" arc, scoped down
    /// to a single device: mama's view model produces ten audio chunks
    /// against a `PersistentDatabase`. The cloud is constructed but
    /// untouched; no marina; no remote propagation.
    ///
    /// Forces `PersistentDatabase` to declare `Database` conformance
    /// (so `VoicesViewModel(database:)` accepts it) and to actually
    /// implement `appendChunk(_:to:)` — without it, `DemoRecordingService
    /// .produceChunks` calls a no-op ten times and the recording stays
    /// at zero chunks.
    @Test("Mama records 10 chunks locally via her view model")
    func mamaRecordsTenChunksLocallyViaHerViewModel() async throws {
        let urlMama = FileManager.default.temporaryDirectory
            .appending(path: "scratch-mama-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: urlMama) }

        let cloud = InMemoryCloud()
        let mamaDB = PersistentDatabase(localFileURL: urlMama, cloud: cloud)

        let mamaID = UUID()
        let mama = VoicesViewModel(
            recordingService: DemoRecordingService(database: mamaDB, author: mamaID, count: 10),
            playbackService: DemoPlaybackService(database: mamaDB, viewer: mamaID),
            database: mamaDB,
            viewer: mamaID
        )

        mama.toggleRecording()
        // delay: .zero makes produceChunks yield via Task.yield(); the
        // 250 ms cap is a fail-fast bound, not a sleep.
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(250))
        while ContinuousClock.now < deadline,
              mama.recordings.flatMap({ $0.audioChunks }).count < 10 {
            await Task.yield()
        }
        mama.toggleRecording()

        #expect(mama.recordings.flatMap { $0.audioChunks }.count == 10)
    }

    /// Two view models on one phone, two `PersistentDatabase` instances
    /// with distinct local file URLs, sharing exactly one `Cloud`.
    /// Mama records; once marina (the listener side) can see more than
    /// one chunk, she starts listening; once mama can see that more
    /// than ten of her chunks have been listened to, she stops. At the
    /// end, the chunks marina's playback spy captured are compared to
    /// the chunks marked listened on mama's side.
    ///
    /// All actions are user-level (`toggleRecording`, `toggleListening`).
    /// The test does NOT call `pushToRemote`, `pullFromRemote`, or any
    /// other cloud method — propagation is the production's
    /// responsibility.
    @Test("Marina plays once she sees mama's chunks; mama stops once she sees marina's marks; spy matches mama's listened chunks")
    func marinaPlaysAndMamaReflectsTheSpyChunksViaCloud() async throws {
        let urlMama = FileManager.default.temporaryDirectory
            .appending(path: "scratch-mama-\(UUID().uuidString).json")
        let urlMarina = FileManager.default.temporaryDirectory
            .appending(path: "scratch-marina-\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: urlMama)
            try? FileManager.default.removeItem(at: urlMarina)
        }

        let cloud = InMemoryCloud()
        let mamaDB = PersistentDatabase(localFileURL: urlMama, cloud: cloud)
        let marinaDB = PersistentDatabase(localFileURL: urlMarina, cloud: cloud)

        let mamaID = UUID()
        let marinaID = UUID()

        // Hold marina's playback service explicitly so the test can read
        // its `playedChunks` spy after the action sequence completes.
        let marinaPlayback = DemoPlaybackService(database: marinaDB, viewer: marinaID)

        let mama = VoicesViewModel(
            recordingService: DemoRecordingService(database: mamaDB, author: mamaID),
            playbackService: DemoPlaybackService(database: mamaDB, viewer: mamaID),
            database: mamaDB,
            viewer: mamaID
        )

        let marina = VoicesViewModel(
            recordingService: DemoRecordingService(database: marinaDB, author: marinaID),
            playbackService: marinaPlayback,
            database: marinaDB,
            viewer: marinaID
        )

        // Mama starts recording.
        mama.toggleRecording()

        // Wait for marina to see > 1 chunk via cross-device propagation.
        // The test does nothing to make that happen — it just observes.
        let deadline1 = ContinuousClock.now.advanced(by: .seconds(3))
        while ContinuousClock.now < deadline1,
              marina.recordings.flatMap({ $0.audioChunks }).count <= 1 {
            await Task.yield()
        }

        // Marina starts listening.
        marina.toggleListening()

        // Wait until mama can see that > 10 of her chunks have been
        // listened to — again, only via cloud-side propagation.
        let deadline2 = ContinuousClock.now.advanced(by: .seconds(3))
        while ContinuousClock.now < deadline2,
              mama.recordings.flatMap({ $0.audioChunks }).filter({ $0.listened }).count <= 10 {
            await Task.yield()
        }

        // Mama stops.
        mama.toggleRecording()

        // Compare: chunks the listener's spy captured vs. chunks marked
        // listened on the recorder's side.
        let spy = marinaPlayback.playedChunks
        try #require(mama.recordings.flatMap({ $0.audioChunks }).count > 10)
        try #require(spy.count > 0)

        let mamaListenedCount = mama.recordings.flatMap({ $0.audioChunks }).filter({ $0.listened }).count
        #expect(spy.count == mamaListenedCount)
        for pos in spy {
            let listenedOnMama = mama.recordings.first { $0.id == pos.recordingID }?
                .audioChunks.first { $0.index == pos.chunkIndex }?.listened == true
            #expect(listenedOnMama)
        }
    }
}
