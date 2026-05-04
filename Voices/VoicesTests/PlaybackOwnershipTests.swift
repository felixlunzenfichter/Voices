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
}
