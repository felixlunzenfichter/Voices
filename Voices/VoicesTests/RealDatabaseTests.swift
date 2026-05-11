import Foundation
import Testing
@testable import Voices

@Suite(.serialized)
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

        let cloud = HTTPCloud(url: URL(string: "http://felixs-macbook-pro.tailcfdca5.ts.net:9995")!)
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

        let cloud = HTTPCloud(url: URL(string: "http://felixs-macbook-pro.tailcfdca5.ts.net:9995")!)
        let mamaDB = PersistentDatabase(localFileURL: urlMama, cloud: cloud)
        let marinaDB = PersistentDatabase(localFileURL: urlMarina, cloud: cloud)

        let mamaID = UUID()
        let marinaID = UUID()

        // Hold marina's playback service explicitly so the test can read
        // its `playedChunks` spy after the action sequence completes.
        // 10 ms cadence so playback transitions are visible at human-ish rates.
        let marinaPlayback = DemoPlaybackService(database: marinaDB, viewer: marinaID, delay: .milliseconds(10))

        let mama = VoicesViewModel(
            // 10 ms cadence on the recording side too — a chunk every 10 ms.
            recordingService: DemoRecordingService(database: mamaDB, author: mamaID, delay: .milliseconds(10)),
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
        // The player no longer stops on momentary catch-up (it idle-waits
        // up to 5 s for the next chunk), so a 1-chunk head start is
        // enough.
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

        // Wait until marina's playback has drained — `isListening == false` —
        // so the spy vs. recorder comparison happens against settled state,
        // not while playback is mid-flight.
        let deadline3 = ContinuousClock.now.advanced(by: .seconds(3))
        while ContinuousClock.now < deadline3, marina.isListening {
            await Task.yield()
        }

        // Wait until mama's view has caught up: every mark marina
        // locally minted should have round-tripped through POST →
        // server broadcast → mama's SSE → applyRemote before we
        // assert. spy is frozen here because consumePlayback has
        // already exited (wait3).
        let spyTarget = marinaPlayback.playedChunks.count
        let deadline4 = ContinuousClock.now.advanced(by: .seconds(2))
        while ContinuousClock.now < deadline4,
              mama.recordings.flatMap({ $0.audioChunks }).filter({ $0.listened }).count < spyTarget {
            await Task.yield()
        }

        // Compare: chunks the listener's spy captured vs. chunks marked
        // listened on the recorder's side. State is settled (wait3+wait4),
        // so snapshot mama-side bindings once and read from them.
        let spy = marinaPlayback.playedChunks
        let mamaRecordings = mama.recordings
        let mamaChunks = mamaRecordings.flatMap { $0.audioChunks }
        let mamaListenedCount = mamaChunks.filter(\.listened).count

        try #require(mamaChunks.count > 10)
        try #require(spy.count > 10)
        #expect(spy.count == mamaListenedCount)
        for pos in spy {
            let listenedOnMama = mamaRecordings.first { $0.id == pos.recordingID }?
                .audioChunks.first { $0.index == pos.chunkIndex }?.listened == true
            #expect(listenedOnMama)
        }
    }

    /// Live-refresh contract: `VoicesViewModel.recordings` must wake
    /// up observers when the underlying `PersistentDatabase` mutates.
    /// No polling — the test subscribes via Swift's `Observations`
    /// AsyncSequence, then triggers `db.appendChunk` on a separate
    /// turn so the wake-up is the *only* path that can complete it.
    /// Fail-fast bound is 2 s; expected wake-up under a working
    /// implementation is <100 ms.
    ///
    /// Fails if `PersistentDatabase` is not `@Observable`: the
    /// `inner` mutation never reaches the Observation framework,
    /// the observer Task never sets `observed`, and the deadline
    /// expires with `#expect(observed)` failing.
    @Test("VoicesViewModel observes database mutations reactively, without polling")
    func vmObservesDatabaseMutationsLive() async throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "live-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let cloud = HTTPCloud(url: URL(string: "http://felixs-macbook-pro.tailcfdca5.ts.net:9995")!)
        let db = PersistentDatabase(localFileURL: url, cloud: cloud)

        let viewer = UUID()
        let author = UUID()
        let vm = VoicesViewModel(
            recordingService: DemoRecordingService(database: db, author: author),
            playbackService: DemoPlaybackService(database: db, viewer: viewer),
            database: db,
            viewer: viewer
        )

        let target = UUID()
        db.addRecording(Recording(id: target, author: author))

        // Reactive observer: yields once on first evaluation, then again
        // every time the @Observable storage backing `vm.recordings`
        // is modified. Sets `observed` when a chunk lands.
        nonisolated(unsafe) var observed = false
        let observer = Task { @MainActor in
            for await count in Observations({
                vm.recordings.first(where: { $0.id == target })?.audioChunks.count ?? 0
            }) {
                if count >= 1 {
                    observed = true
                    return
                }
            }
        }

        // Mutate on a future turn so the observer is already subscribed
        // before the change happens; otherwise the first iteration
        // would yield the post-mutation value trivially.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            db.appendChunk(AudioChunk(index: 0), to: target)
        }

        // Tight fail-fast — a working implementation wakes in <100 ms.
        try? await Task.sleep(for: .seconds(2))
        observer.cancel()

        #expect(observed)
    }
}
