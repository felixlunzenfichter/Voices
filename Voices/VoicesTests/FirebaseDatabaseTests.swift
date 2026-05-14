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
}
