import Foundation
import Observation
import Testing
@testable import Voices

@MainActor
struct PlaybackOwnershipTests {

    @Test("Listening to Marina's message marks chunks as listenedBy Mama", .timeLimit(.minutes(1)))
    func listeningToForeignMessageMarksViewer() async {
        let mama = Participant.mama
        let (vm, db) = VoicesViewModel.viewerWithForeignMessage(
            viewer: mama,
            author: .marina,
            chunkCount: 3
        )

        vm.toggleListening()
        for await listening in Observations({ vm.isListening }) {
            if !listening { break }
        }

        let chunks = db.conversations.first!.recordings.first!.audioChunks
        #expect(chunks.allSatisfy { $0.listenedBy == [mama.id] })
    }

    @Test("Listening to my own message does not mark me as a listener", .timeLimit(.minutes(1)))
    func listeningToOwnMessageDoesNotMarkSelf() async {
        let mama = Participant.mama
        let (vm, db) = VoicesViewModel.viewerWithOwnMessage(
            viewer: mama,
            chunkCount: 3
        )

        // Own messages don't count as unplayed, so toggleListening alone is a
        // no-op. Force playback by seeking first.
        vm.seekTo(0)
        vm.toggleListening()
        for await listening in Observations({ vm.isListening }) {
            if !listening { break }
        }

        let chunks = db.conversations.first!.recordings.first!.audioChunks
        #expect(chunks.allSatisfy { $0.listenedBy.isEmpty })
        #expect(chunks.allSatisfy { !$0.listenedBy.contains(mama.id) })
    }

    @Test("Remote simulated cursor is nil before heartbeats and points to the last listened chunk after",
          .timeLimit(.minutes(1)))
    func simulatedCursorIsNilBeforeAndLastChunkAfter() async throws {
        let (recorderVM, listenerVM, _) = VoicesViewModel.pairOfViewers(
            recorder: .marina, listener: .mama, chunkCount: 3
        )

        #expect(recorderVM.simulatedPlaybackCursor(for: Participant.mama.id) == nil)

        listenerVM.toggleListening()
        for await playing in Observations({ listenerVM.isListening }) {
            if !playing { break }
        }

        let recording = try #require(recorderVM.recordings.first)
        let lastChunk = PlaybackPosition(
            recordingID: recording.id,
            chunkIndex: recording.audioChunks.count - 1
        )
        #expect(recorderVM.simulatedPlaybackCursor(for: Participant.mama.id) == lastChunk)
    }
}
