import Foundation
import AVFoundation
import Testing
@testable import Voices

@MainActor
@Suite(.serialized)
struct RealRecordingServiceTests {

    /// Smallest honest red for the real-audio seam. The producer writes
    /// to the conventional path; the database carries only the chunk
    /// index. The test computes the path from the same convention the
    /// service uses and verifies the bytes are real AAC.
    @Test("RealRecordingService writes one decodable AAC chunk to the conventional path",
          .timeLimit(.minutes(1)))
    func realRecordingWritesDecodableChunkToConventionalPath() async throws {
        let database = InMemoryDatabase()
        let service = RealRecordingService(database: database, author: UUID())

        service.start()

        for await count in Observations({ database.recordings.first?.audioChunks.count })
            where (count ?? 0) >= 1 {
            break
        }

        service.stop()

        let recording = try #require(database.recordings.first)
        let chunk = try #require(recording.audioChunks.first)
        let url = chunkFileURL(recordingID: recording.id, chunkIndex: chunk.index)

        let size = try #require(
            FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int
        )
        #expect(size > 0)

        let file = try AVAudioFile(forReading: url)
        #expect(file.length > 0)
    }
}
