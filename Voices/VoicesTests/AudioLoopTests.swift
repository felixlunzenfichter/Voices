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
          .timeLimit(.minutes(3)))
    func audioLoopRecordsPersistsAndPlaysBack() async throws {
        try await FirebaseFixture.fresh()
        let suffix = UUID().uuidString.prefix(6)
        let writer = FirebaseFixture.makeDatabase(appName: "writer-\(suffix)")
        let reader = FirebaseFixture.makeDatabase(appName: "reader-\(suffix)")
        let viewer = UUID()
        let author = UUID()
        let recorder = RealRecordingService(database: writer, author: author)
        let player = RealPlaybackService(database: reader, viewer: viewer)

        let total = Date()
        let recordStart = Date()
        recorder.start()
        // Wait for the READER to see 30 chunks — i.e. they round-tripped
        // through the emulator, not through writer-side cache.
        for await count in Observations({ reader.recordings.first?.audioChunks.count })
            where (count ?? 0) >= 100 { break }
        recorder.stop()
        let recordDuration = Date().timeIntervalSince(recordStart)

        let chunk = try #require(reader.recordings.first?.audioChunks.first)
        #expect(chunk.data.count > 0, "persisted chunk must carry real PCM bytes")

        let playStart = Date()
        player.play()
        for await everyListened in Observations({
            reader.recordings.first?.audioChunks.allSatisfy(\.listened) ?? false
        }) where everyListened { break }
        player.stop()
        let playDuration = Date().timeIntervalSince(playStart)
        let totalDuration = Date().timeIntervalSince(total)

        print("""
        ===== AUDIO LOOP (30 chunks, writer/reader pair, Firestore inline) =====
        total            \(String(format: "%.3f", totalDuration)) s
          recording      \(String(format: "%.3f", recordDuration)) s
          playback       \(String(format: "%.3f", playDuration)) s
        =======================================================================
        """)
    }
}
