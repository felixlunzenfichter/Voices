import Foundation
import AVFoundation
import Testing
@testable import Voices

@MainActor
@Suite(.serialized)
struct AudioLoopTests {

    /// Smallest end-to-end red for the bundled audio loop: a real
    /// recording, persisted by the real `FirebaseDatabase`, and
    /// consumed by `RealPlaybackService` through the existing
    /// `PlaybackService.play()` entry. Every chunk must end up
    /// marked listened by the viewer, which is the contract the
    /// demo player already fulfils against the in-memory database.
    @Test("Audio loop: record → persist via FirebaseDatabase → play back, every chunk listened",
          .timeLimit(.minutes(1)))
    func audioLoopRecordsPersistsAndPlaysBack() async throws {
        try await FirebaseFixture.fresh()
        let database = FirebaseFixture.makeDatabase(appName: "loop")
        let viewer = UUID()
        let author = UUID()
        let recorder = RealRecordingService(database: database, author: author)
        let player = RealPlaybackService(database: database, viewer: viewer)

        recorder.start()
        for await count in Observations({ database.recordings.first?.audioChunks.count })
            where (count ?? 0) >= 1 { break }
        recorder.stop()

        let chunk = try #require(database.recordings.first?.audioChunks.first)
        #expect(chunk.data.count > 0, "persisted chunk must carry real AAC bytes")

        player.play()
        for await everyListened in Observations({
            database.recordings.first?.audioChunks.allSatisfy(\.listened) ?? false
        }) where everyListened { break }
        player.stop()
    }
}
