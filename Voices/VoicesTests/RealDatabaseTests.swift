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
}
