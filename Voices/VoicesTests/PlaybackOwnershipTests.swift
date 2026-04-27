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
}
