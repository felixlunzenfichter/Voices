import Foundation
import Observation
import FirebaseFirestore

@Observable @MainActor
final class FirebaseDatabase: Database {
    var recordings: [Recording] = []

    @ObservationIgnored
    nonisolated private let firestore: Firestore

    @ObservationIgnored
    nonisolated(unsafe) private var listenerRegistration: ListenerRegistration?

    init(firestore: Firestore = Firestore.firestore()) {
        self.firestore = firestore
        listenerRegistration = firestore.collection("recordings").addSnapshotListener { [weak self] snapshot, _ in
            MainActor.assumeIsolated {
                guard let self, let docs = snapshot?.documents else { return }
                self.recordings = docs.compactMap(Self.recording(from:))
            }
        }
    }

    nonisolated deinit {
        listenerRegistration?.remove()
    }

    func addRecording(_ recording: Recording) {
        firestore.collection("recordings").document(recording.id.uuidString).setData([
            "id": recording.id.uuidString,
            "author": recording.author.uuidString
        ])
    }

    func appendChunk(_ chunk: AudioChunk, to recordingID: UUID) {}
    func removeRecording(_ recordingID: UUID) {}
    func markListened(recordingID: UUID, chunkIndex: Int) {}
    func markListened(recordingID: UUID, chunkIndex: Int, by viewerID: UUID) {}

    private static func recording(from doc: QueryDocumentSnapshot) -> Recording? {
        let data = doc.data()
        guard let idStr = data["id"] as? String, let id = UUID(uuidString: idStr),
              let authorStr = data["author"] as? String, let author = UUID(uuidString: authorStr)
        else { return nil }
        return Recording(id: id, author: author, audioChunks: [])
    }
}
