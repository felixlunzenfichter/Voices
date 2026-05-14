import Foundation
import Testing
@testable import Voices

@MainActor
@Suite(.serialized)
struct FirebaseDatabaseTests {

    /// Smallest honest red for the cloud seam: one FirebaseDatabase
    /// against the Firestore emulator. Writing a recording must surface
    /// in the same instance's observed `recordings` array within 3 s
    /// (the snapshot listener round-trips through the emulator).
    @Test("Adding a recording surfaces in the same database's recordings within 3s",
          .timeLimit(.minutes(1)))
    func addedRecordingAppears() async throws {
        try await FirebaseFixture.fresh()
        let db = FirebaseDatabase()

        db.addRecording(Recording(id: UUID(), author: UUID()))

        let deadline = Date().addingTimeInterval(3)
        while db.recordings.count < 1, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(db.recordings.count == 1)
    }

    /// Two FirebaseDatabase instances backed by separate FirebaseApp
    /// configurations have independent Firestore clients and
    /// independent caches. The only way a write through `writer` can
    /// reach `reader.recordings` is via the emulator's listen stream,
    /// so a green result here proves the network round-trip.
    @Test("A recording written through one Firebase instance reaches another via the emulator",
          .timeLimit(.minutes(1)))
    func crossInstancePropagation() async throws {
        try await FirebaseFixture.fresh()
        let writer = FirebaseFixture.makeDatabase(appName: "writer")
        let reader = FirebaseFixture.makeDatabase(appName: "reader")

        let recording = Recording(id: UUID(), author: UUID())
        writer.addRecording(recording)

        let deadline = Date().addingTimeInterval(5)
        while reader.recordings.first?.id != recording.id, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(reader.recordings.map(\.id) == [recording.id])
    }

    /// Smallest same-instance check for chunk append: after adding a
    /// recording and appending a chunk, the same database's observed
    /// `audioChunks` must reflect the appended chunk.
    @Test("Appending a chunk surfaces in the same database's recording within 3s",
          .timeLimit(.minutes(1)))
    func appendedChunkAppears() async throws {
        try await FirebaseFixture.fresh()
        let db = FirebaseDatabase()

        let recording = Recording(id: UUID(), author: UUID())
        db.addRecording(recording)
        db.appendChunk(AudioChunk(index: 0), to: recording.id)

        let deadline = Date().addingTimeInterval(3)
        while db.recordings.first?.audioChunks.isEmpty != false, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(db.recordings.first?.audioChunks == [AudioChunk(index: 0)])
    }

    /// Cross-instance chunk propagation: a chunk appended through one
    /// FirebaseDatabase must surface in another, independently-backed
    /// instance via the emulator's listen stream.
    @Test("A chunk appended through one Firebase instance reaches another via the emulator",
          .timeLimit(.minutes(1)))
    func appendedChunkPropagates() async throws {
        try await FirebaseFixture.fresh()
        let writer = FirebaseFixture.makeDatabase(appName: "writer")
        let reader = FirebaseFixture.makeDatabase(appName: "reader")

        let recording = Recording(id: UUID(), author: UUID())
        writer.addRecording(recording)
        writer.appendChunk(AudioChunk(index: 0), to: recording.id)

        let deadline = Date().addingTimeInterval(5)
        while reader.recordings.first?.audioChunks.isEmpty != false, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(reader.recordings.first?.audioChunks == [AudioChunk(index: 0)])
    }

    /// Smallest same-instance check for listened-mark propagation:
    /// marking a chunk listened must flip its `listened` flag in the
    /// same database's observed `audioChunks` within 3 s.
    @Test("Marking a chunk listened surfaces in the same database within 3s",
          .timeLimit(.minutes(1)))
    func markListenedSurfacesLocally() async throws {
        try await FirebaseFixture.fresh()
        let db = FirebaseDatabase()

        let recording = Recording(id: UUID(), author: UUID())
        db.addRecording(recording)
        db.appendChunk(AudioChunk(index: 0), to: recording.id)
        db.markListened(recordingID: recording.id, chunkIndex: 0)

        let deadline = Date().addingTimeInterval(3)
        while db.recordings.first?.audioChunks.first?.listened != true, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(db.recordings.first?.audioChunks.first?.listened == true)
    }

    /// Cross-instance listened-mark propagation: marking a chunk
    /// listened through one FirebaseDatabase must flip the flag in
    /// another, independently-backed instance via the emulator.
    @Test("A listened-mark made through one Firebase instance reaches another via the emulator",
          .timeLimit(.minutes(1)))
    func markListenedPropagates() async throws {
        try await FirebaseFixture.fresh()
        let writer = FirebaseFixture.makeDatabase(appName: "writer")
        let reader = FirebaseFixture.makeDatabase(appName: "reader")

        let recording = Recording(id: UUID(), author: UUID())
        writer.addRecording(recording)
        writer.appendChunk(AudioChunk(index: 0), to: recording.id)
        writer.markListened(recordingID: recording.id, chunkIndex: 0)

        let deadline = Date().addingTimeInterval(5)
        while reader.recordings.first?.audioChunks.first?.listened != true, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(reader.recordings.first?.audioChunks.first?.listened == true)
    }
}
