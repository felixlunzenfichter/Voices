import Foundation
import Testing
@testable import Voices

@Suite(.serialized)
@MainActor
struct RealDatabaseTests {

    /// Two view models on one phone, two `PersistentDatabase` instances
    /// with distinct local file URLs, sharing exactly one `Cloud`.
    /// Mama records; once marina (the listener side) can see more than
    /// one chunk, she starts listening; once mama can see that more
    /// than ten of her chunks have been listened to, she stops. At the
    /// end, the chunks marina's playback spy captured are compared to
    /// the chunks marked listened on mama's side.
    ///
    /// All actions are user-level (`toggleRecording`, `toggleListening`).
    /// The test does NOT call any cloud method — propagation is the
    /// production's responsibility.
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
        // The player must not stop on momentary catch-up, so a 1-chunk
        // head start is enough.
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
        // locally minted should have round-tripped through the cloud
        // before we assert. spy is frozen here because consumePlayback
        // has already exited (wait3).
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

    /// Both A and B advance their local state while offline, then both
    /// reconnect to the real Mac and have to merge.
    ///
    /// Phase 1 — both flipped offline at init. Each writes locally
    /// (add a recording + 5 chunks). Mutations apply to the local
    /// projection immediately; the outbound queue accumulates and
    /// the drainer parks because `online == false`.
    ///
    /// Phase 2 — both flipped online. Each drainer pumps its queue
    /// against the real Mac. One side wins the race; the other gets
    /// 409, applies the missed events, and retries from its head
    /// with the new cursor. Both subscriber streams open with
    /// `since: cursor` and pick up everything the other side wrote.
    ///
    /// Expected merged result: both dbA and dbB see TWO recordings
    /// (rA and rB), 5 chunks each, 10 chunks total, and the same
    /// set of recording ids.
    ///
    /// Production seam: a persisted outbound queue on
    /// PersistentDatabase + a drainer that respects an `online`
    /// gate and handles CAS retry on 409. Today every mutation
    /// fires fire-and-forget; offline writes are lost.
    @Test("Both devices advanced offline, then merge cleanly on reconnect",
          .timeLimit(.minutes(1)))
    func bothSidesAdvancedOfflineThenMerge() async throws {
        let urlA = FileManager.default.temporaryDirectory
            .appending(path: "offline-A-\(UUID().uuidString).json")
        let urlB = FileManager.default.temporaryDirectory
            .appending(path: "offline-B-\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: urlA)
            try? FileManager.default.removeItem(at: urlB)
        }

        // Reset the real Mac to empty history.
        let macURL = URL(string: "http://felixs-macbook-pro.tailcfdca5.ts.net:9995")!
        var resetRequest = URLRequest(url: macURL.appending(path: "reset"))
        resetRequest.httpMethod = "POST"
        _ = try? await URLSession.shared.data(for: resetRequest)

        let αA = UUID()
        let αB = UUID()
        let rA = Recording(author: αA)
        let rB = Recording(author: αB)

        let cloud = HTTPCloud(url: macURL)

        // Phase 1 — both offline. Single instance per side; survives
        // the offline → online transition without reinstantiation.
        let dbA = PersistentDatabase(localFileURL: urlA, cloud: cloud, online: false)
        let dbB = PersistentDatabase(localFileURL: urlB, cloud: cloud, online: false)

        dbA.addRecording(rA)
        for i in 0..<5 { dbA.appendChunk(AudioChunk(index: i), to: rA.id) }
        dbB.addRecording(rB)
        for i in 0..<5 { dbB.appendChunk(AudioChunk(index: i), to: rB.id) }

        // Local writes applied immediately; neither side sees the other yet.
        #expect(dbA.recordings.count == 1)
        #expect(dbB.recordings.count == 1)

        // Phase 2 — both online. Drainers pump, CAS retries, subscribers
        // pick up each other's events.
        dbA.setOnline(true)
        dbB.setOnline(true)

        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while ContinuousClock.now < deadline {
            let aRecs = dbA.recordings
            let bRecs = dbB.recordings
            let aChunks = aRecs.flatMap { $0.audioChunks }.count
            let bChunks = bRecs.flatMap { $0.audioChunks }.count
            if aRecs.count == 2, bRecs.count == 2, aChunks == 10, bChunks == 10 {
                break
            }
            await Task.yield()
        }

        let aRecs = dbA.recordings
        let bRecs = dbB.recordings
        #expect(aRecs.count == 2)
        #expect(bRecs.count == 2)
        #expect(aRecs.flatMap { $0.audioChunks }.count == 10)
        #expect(bRecs.flatMap { $0.audioChunks }.count == 10)
        #expect(Set(aRecs.map(\.id)) == Set(bRecs.map(\.id)))
        #expect(aRecs.contains(where: { $0.id == rA.id }))
        #expect(aRecs.contains(where: { $0.id == rB.id }))
        #expect(bRecs.contains(where: { $0.id == rA.id }))
        #expect(bRecs.contains(where: { $0.id == rB.id }))
    }
}
