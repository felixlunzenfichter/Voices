import Foundation
import Observation
import FirebaseFirestore

/// Hybrid backend:
/// - Firestore holds metadata + chunk index sets + listened set.
/// - Mac blob server holds raw audio bytes per chunk.
/// - The Database adapter writes bytes locally first (durable), then
///   the Firestore listener drives the upload/download work loops.
@Observable @MainActor
final class FirebaseDatabase: Database {
    var recordings: [Recording] = []

    @ObservationIgnored nonisolated private let firestore: Firestore
    @ObservationIgnored nonisolated private let macServerBase: URL
    @ObservationIgnored nonisolated(unsafe) private var listenerRegistration: ListenerRegistration?

    /// Disk namespace for cached chunk bytes. Stable across app
    /// launches in production (default "default"), so relaunches
    /// find their previously-downloaded chunks. Tests override it to
    /// keep multiple in-process instances isolated.
    @ObservationIgnored private let cacheNamespace: String

    // Single-flight guards for the recursive work loops.
    @ObservationIgnored private var uploadingActive = false
    @ObservationIgnored private var downloadingActive = false

    init(
        firestore: Firestore = Firestore.firestore(),
        macServerBase: URL = URL(string: "http://100.73.64.63:7654")!,
        cacheNamespace: String = "default"
    ) {
        self.firestore = firestore
        self.macServerBase = macServerBase
        self.cacheNamespace = cacheNamespace
        listenerRegistration = firestore.collection("recordings")
            .order(by: "createdAt")
            .addSnapshotListener { [weak self] snapshot, _ in
                MainActor.assumeIsolated {
                    guard let self, let snapshot else { return }
                    self.applySnapshot(snapshot)
                }
            }
    }

    nonisolated deinit { listenerRegistration?.remove() }

    // MARK: - Database protocol

    func addRecording(_ recording: Recording) {
        firestore.collection("recordings").document(recording.id.uuidString).setData([
            "id": recording.id.uuidString,
            "author": recording.author.uuidString,
            "createdAt": FieldValue.serverTimestamp(),
            "pendingChunks":  [Int](),
            "uploadedChunks": [Int](),
            "listened":       [Int](),
        ])
    }

    func appendChunk(_ chunk: AudioChunk, to recordingID: UUID) {
        // 1. Write bytes durably to local disk.
        let pcm = pcmURL(recordingID: recordingID, chunkIndex: chunk.index)
        try? FileManager.default.createDirectory(
            at: pcm.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? chunk.data.write(to: pcm)
        // 2. Announce as pending. Firestore SDK fires the listener
        //    locally with hasPendingWrites=true so writer's own UI
        //    sees the chunk immediately.
        firestore.collection("recordings").document(recordingID.uuidString).updateData([
            "pendingChunks": FieldValue.arrayUnion([chunk.index])
        ])
    }

    func removeRecording(_ recordingID: UUID) {}

    func markListened(recordingID: UUID, chunkIndex: Int) {
        firestore.collection("recordings").document(recordingID.uuidString).updateData([
            "listened": FieldValue.arrayUnion([chunkIndex])
        ])
    }

    func markListened(recordingID: UUID, chunkIndex: Int, by viewerID: UUID) {
        guard let rec = recordings.first(where: { $0.id == recordingID }),
              rec.author != viewerID else { return }
        // Firestore is the sole authority for `listened`. The listener
        // fires locally (hasPendingWrites=true) the instant this write
        // is enqueued, so `recordings` reflects the change without any
        // pre-emptive mutation here.
        let docRef = firestore.collection("recordings").document(recordingID.uuidString)
        Task {
            try? await docRef.updateData(["listened": FieldValue.arrayUnion([chunkIndex])])
        }
    }

    // MARK: - Snapshot ingestion — sole writer of `recordings`.

    /// Mutate only the slots Firestore reports changed. Untouched
    /// recordings keep their existing in-memory `AudioChunk`s.
    private func applySnapshot(_ snapshot: QuerySnapshot) {
        for change in snapshot.documentChanges {
            guard let recording = recording(from: change.document) else { continue }
            switch change.type {
            case .added:
                recordings.insert(recording, at: Int(change.newIndex))
            case .modified:
                if change.oldIndex == change.newIndex {
                    recordings[Int(change.newIndex)] = recording
                } else {
                    recordings.remove(at: Int(change.oldIndex))
                    recordings.insert(recording, at: Int(change.newIndex))
                }
            case .removed:
                recordings.remove(at: Int(change.oldIndex))
            @unknown default:
                break
            }
        }
        driveUploads()
        driveDownloads()
    }

    /// Parse one Firestore doc into a Recording, with `AudioChunk`s
    /// carrying their two availability flags. No persistent state
    /// outside `recordings`.
    private func recording(from doc: QueryDocumentSnapshot) -> Recording? {
        let data = doc.data()
        guard let idStr = data["id"] as? String, let id = UUID(uuidString: idStr),
              let authorStr = data["author"] as? String, let author = UUID(uuidString: authorStr)
        else { return nil }
        let pending  = Set((data["pendingChunks"]  as? [Any] ?? []).compactMap { $0 as? Int })
        let uploaded = Set((data["uploadedChunks"] as? [Any] ?? []).compactMap { $0 as? Int })
        let listened = Set((data["listened"]       as? [Any] ?? []).compactMap { $0 as? Int })

        let indices = pending.union(uploaded).sorted()
        let chunks = indices.map { idx -> AudioChunk in
            let local = fileExists(rid: id, idx: idx)
            let bytes = local
                ? (try? Data(contentsOf: pcmURL(recordingID: id, chunkIndex: idx))) ?? Data()
                : Data()
            return AudioChunk(
                index: idx,
                data: bytes,
                listened: listened.contains(idx),
                isAvailableOffline: local,
                isAvailableOnline:  uploaded.contains(idx)
            )
        }
        return Recording(id: id, author: author, audioChunks: chunks)
    }

    // MARK: - Recursive work loops

    private func driveUploads() {
        guard !uploadingActive else { return }
        uploadingActive = true
        Task { await uploadOne() }
    }

    private func uploadOne() async {
        guard let (rid, idx) = findNextPending() else {
            uploadingActive = false
            return
        }
        let ok = await uploadAndConfirm(rid: rid, idx: idx)
        guard ok else {
            uploadingActive = false
            return
        }
        await uploadOne()
    }

    /// A chunk to upload = bytes are local but server hasn't confirmed
    /// upload yet. Pure scan of the observable `recordings` array.
    private func findNextPending() -> (UUID, Int)? {
        for rec in recordings {
            for chunk in rec.audioChunks
            where chunk.isAvailableOffline && !chunk.isAvailableOnline {
                return (rec.id, chunk.index)
            }
        }
        return nil
    }

    private func uploadAndConfirm(rid: UUID, idx: Int) async -> Bool {
        let pcm = pcmURL(recordingID: rid, chunkIndex: idx)
        guard let bytes = try? Data(contentsOf: pcm) else { return false }
        do {
            try await macPut(rid: rid, idx: idx, data: bytes)
        } catch {
            return false
        }
        let docRef = firestore.collection("recordings").document(rid.uuidString)
        do {
            try await docRef.updateData([
                "pendingChunks":  FieldValue.arrayRemove([idx]),
                "uploadedChunks": FieldValue.arrayUnion([idx]),
            ])
        } catch {
            return false
        }
        return true
    }

    private func driveDownloads() {
        guard !downloadingActive else { return }
        downloadingActive = true
        Task { await downloadOne() }
    }

    private func downloadOne() async {
        guard let (rid, idx) = findNextDownload() else {
            downloadingActive = false
            return
        }
        let ok = await downloadAndStore(rid: rid, idx: idx)
        guard ok else {
            downloadingActive = false
            return
        }
        await downloadOne()
    }

    /// A chunk to download = server has bytes but we don't have them
    /// locally. Pure scan of the observable `recordings` array.
    private func findNextDownload() -> (UUID, Int)? {
        for rec in recordings {
            for chunk in rec.audioChunks
            where chunk.isAvailableOnline && !chunk.isAvailableOffline {
                return (rec.id, chunk.index)
            }
        }
        return nil
    }

    private func downloadAndStore(rid: UUID, idx: Int) async -> Bool {
        let bytes: Data
        do { bytes = try await macGet(rid: rid, idx: idx) } catch { return false }
        let pcm = pcmURL(recordingID: rid, chunkIndex: idx)
        try? FileManager.default.createDirectory(
            at: pcm.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        do { try bytes.write(to: pcm) } catch { return false }
        // Direct mutation of the observable state: flip
        // isAvailableOffline + populate bytes on this one chunk.
        if let rIdx = recordings.firstIndex(where: { $0.id == rid }),
           let cIdx = recordings[rIdx].audioChunks.firstIndex(where: { $0.index == idx }) {
            recordings[rIdx].audioChunks[cIdx].data = bytes
            recordings[rIdx].audioChunks[cIdx].isAvailableOffline = true
        }
        return true
    }

    // MARK: - Mac blob client

    private func macPut(rid: UUID, idx: Int, data: Data) async throws {
        var req = URLRequest(url: blobURL(rid: rid, idx: idx))
        req.httpMethod = "PUT"
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    private func macGet(rid: UUID, idx: Int) async throws -> Data {
        let (data, resp) = try await URLSession.shared.data(from: blobURL(rid: rid, idx: idx))
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.fileDoesNotExist)
        }
        return data
    }

    private func blobURL(rid: UUID, idx: Int) -> URL {
        macServerBase.appendingPathComponent("blobs/\(rid.uuidString)/\(idx)")
    }

    // MARK: - Local disk

    private func pcmURL(recordingID: UUID, chunkIndex: Int) -> URL {
        // Library/Caches survives normal app lifecycle (unlike tmp)
        // while still being purge-eligible under disk pressure.
        let base = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("voices-firebase-cache/\(cacheNamespace)/\(recordingID.uuidString)/\(chunkIndex).pcm")
    }

    private func fileExists(rid: UUID, idx: Int) -> Bool {
        FileManager.default.fileExists(atPath: pcmURL(recordingID: rid, chunkIndex: idx).path)
    }
}
