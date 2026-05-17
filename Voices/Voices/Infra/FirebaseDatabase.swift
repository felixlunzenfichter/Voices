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
        listenerRegistration = firestore.collection("recordings")
            .order(by: "createdAt")
            .addSnapshotListener { [weak self] snapshot, _ in
                MainActor.assumeIsolated {
                    guard let self, let snapshot else { return }
                    for change in snapshot.documentChanges {
                        guard let recording = Self.recording(from: change.document) else { continue }
                        switch change.type {
                        case .added:
                            self.recordings.insert(recording, at: Int(change.newIndex))
                        case .modified:
                            if change.oldIndex == change.newIndex {
                                self.recordings[Int(change.newIndex)] = recording
                            } else {
                                self.recordings.remove(at: Int(change.oldIndex))
                                self.recordings.insert(recording, at: Int(change.newIndex))
                            }
                        case .removed:
                            self.recordings.remove(at: Int(change.oldIndex))
                        @unknown default:
                            break
                        }
                    }
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
            "listened": [Int](),
            "createdAt": FieldValue.serverTimestamp()
        ])
    }

    func appendChunk(_ chunk: AudioChunk, to recordingID: UUID) {
        firestore.collection("recordings").document(recordingID.uuidString).updateData([
            "chunks": FieldValue.arrayUnion([chunk.index]),
            "chunkData.\(chunk.index)": chunk.data.base64EncodedString()
        ])
    }

    func removeRecording(_ recordingID: UUID) {}

    func markListened(recordingID: UUID, chunkIndex: Int) {
        firestore.collection("recordings").document(recordingID.uuidString).updateData([
            "listened": FieldValue.arrayUnion([chunkIndex])
        ])
    }

    /// Viewer-aware: a viewer cannot mark their own recording's chunks
    /// listened. Author is immutable after addRecording, so the
    /// read-then-conditional-write is race-free.
    func markListened(recordingID: UUID, chunkIndex: Int, by viewerID: UUID) {
        let docRef = firestore.collection("recordings").document(recordingID.uuidString)
        Task {
            guard let snap = try? await docRef.getDocument(),
                  let authorStr = snap.data()?["author"] as? String,
                  let authorID = UUID(uuidString: authorStr),
                  authorID != viewerID
            else { return }
            try? await docRef.updateData([
                "listened": FieldValue.arrayUnion([chunkIndex])
            ])
        }
    }

    private static func recording(from doc: QueryDocumentSnapshot) -> Recording? {
        let data = doc.data()
        guard let idStr = data["id"] as? String, let id = UUID(uuidString: idStr),
              let authorStr = data["author"] as? String, let author = UUID(uuidString: authorStr)
        else { return nil }
        let indices = (data["chunks"] as? [Any] ?? []).compactMap { $0 as? Int }
        let listenedSet = Set((data["listened"] as? [Any] ?? []).compactMap { $0 as? Int })
        let chunkDataMap = data["chunkData"] as? [String: String] ?? [:]
        let chunks = indices.map { idx in
            let bytes = chunkDataMap["\(idx)"].flatMap { Data(base64Encoded: $0) } ?? Data()
            return AudioChunk(index: idx, data: bytes, listened: listenedSet.contains(idx))
        }
        return Recording(id: id, author: author, audioChunks: chunks)
    }
}
