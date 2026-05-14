import Foundation
import Observation
import FirebaseFirestore

@Observable @MainActor
final class FirebaseDatabase: Database {
    var recordings: [Recording] = []

    @ObservationIgnored
    nonisolated private let firestore: Firestore

    @ObservationIgnored
    nonisolated private let viewer: UUID

    @ObservationIgnored
    nonisolated(unsafe) private var listenerRegistration: ListenerRegistration?

    init(firestore: Firestore = Firestore.firestore(), viewer: UUID = UUID()) {
        self.firestore = firestore
        self.viewer = viewer
        listenerRegistration = firestore.collection("recordings").addSnapshotListener { [weak self] snapshot, _ in
            MainActor.assumeIsolated {
                guard let self, let docs = snapshot?.documents else { return }
                self.recordings = docs.compactMap { self.recording(from: $0) }
            }
        }
    }

    nonisolated deinit {
        listenerRegistration?.remove()
    }

    func addRecording(_ recording: Recording) {
        firestore.collection("recordings").document(recording.id.uuidString).setData([
            "id": recording.id.uuidString,
            "author": recording.author.uuidString,
            "chunks": recording.audioChunks.map(\.index),
            "listened": [String: [Int]]()
        ])
    }

    func appendChunk(_ chunk: AudioChunk, to recordingID: UUID) {
        firestore.collection("recordings").document(recordingID.uuidString).updateData([
            "chunks": FieldValue.arrayUnion([chunk.index])
        ])
    }

    func removeRecording(_ recordingID: UUID) {}

    func markListened(recordingID: UUID, chunkIndex: Int) {
        markListened(recordingID: recordingID, chunkIndex: chunkIndex, by: viewer)
    }

    func markListened(recordingID: UUID, chunkIndex: Int, by viewerID: UUID) {
        firestore.collection("recordings").document(recordingID.uuidString).updateData([
            "listened.\(viewerID.uuidString)": FieldValue.arrayUnion([chunkIndex])
        ])
    }

    private func recording(from doc: QueryDocumentSnapshot) -> Recording? {
        let data = doc.data()
        guard let idStr = data["id"] as? String, let id = UUID(uuidString: idStr),
              let authorStr = data["author"] as? String, let author = UUID(uuidString: authorStr)
        else { return nil }
        let indices = (data["chunks"] as? [Any] ?? []).compactMap { $0 as? Int }
        let listenedRaw = data["listened"] as? [String: Any] ?? [:]
        let viewerKey = viewer.uuidString
        let listenedSet = Set((listenedRaw[viewerKey] as? [Any] ?? []).compactMap { $0 as? Int })
        let chunks = indices.map { AudioChunk(index: $0, listened: listenedSet.contains($0)) }
        return Recording(id: id, author: author, audioChunks: chunks)
    }
}
