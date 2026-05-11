import Foundation

/// Shared remote store. Each method is a full-snapshot exchange — no
/// deltas, no per-record CRUD. The single conformer in the scratch is
/// `InMemoryCloud` in the test target; a real `MacServerCloud` (or
/// equivalent) is a later concern.
///
/// The cloud carries plain `[Recording]`. Per-device storage state
/// (whether *this* device has a recording on disk, whether *this*
/// device has confirmed it sent that recording to the cloud) is not a
/// property of the recording itself and never crosses the wire.
@MainActor
protocol Cloud: AnyObject {
    func get() async throws -> [Recording]
    func set(_ recordings: [Recording]) async throws
}

/// Local on-disk database keyed by a caller-supplied file URL, paired
/// with a `Cloud` it can push to and pull from.
///
/// Two PersistentDatabase instances sharing the same `Cloud` but using
/// distinct `localFileURL`s model "two devices on one phone". They
/// share nothing locally; cross-device propagation goes only through
/// the cloud, and only when the caller explicitly invokes
/// `pushToRemote()` / `pullFromRemote()`. There is no notification
/// mechanism — B only knows about A's recording when the test asks B
/// to pull.
@MainActor
final class PersistentDatabase: Database {
    /// Local envelope around a `Recording` that carries this device's
    /// per-recording storage state. Lives entirely on disk and in
    /// memory; never sent to the cloud. Two `PersistentDatabase`
    /// instances looking at the same `Recording.id` may have
    /// different `isStoredLocally` / `isStoredRemotely` values
    /// because the flags describe *each device's* knowledge.
    struct StoredRecording: Equatable, Codable {
        var recording: Recording
        var isStoredLocally: Bool
        var isStoredRemotely: Bool

        init(recording: Recording,
             isStoredLocally: Bool = false,
             isStoredRemotely: Bool = false) {
            self.recording = recording
            self.isStoredLocally = isStoredLocally
            self.isStoredRemotely = isStoredRemotely
        }
    }

    private let url: URL
    private let cloud: Cloud
    private var inner: [StoredRecording]

    init(localFileURL: URL, cloud: Cloud) {
        self.url = localFileURL
        self.cloud = cloud
        if let data = try? Data(contentsOf: localFileURL),
           let loaded = try? JSONDecoder().decode([StoredRecording].self, from: data) {
            self.inner = loaded
        } else {
            self.inner = []
        }
    }

    /// `Database` protocol view: plain `[Recording]` for `VoicesViewModel`
    /// and friends, who don't know about per-device storage state.
    var recordings: [Recording] { inner.map { $0.recording } }

    /// Storage-state-aware view: full `[StoredRecording]` for tests and
    /// future UI that wants to display the propagation lifecycle.
    var stored: [StoredRecording] { inner }

    // MARK: - Lifecycle methods that drive flag transitions

    /// Adds a recording locally. `isStoredRemotely` is left at its
    /// default of `false`. `isStoredLocally` is set to `true` only
    /// after the on-disk write actually succeeds; if the write fails,
    /// the recording stays in memory with `isStoredLocally == false`.
    func addRecording(_ recording: Recording) {
        inner.append(StoredRecording(recording: recording))
        guard save() else { return }
        if let i = inner.firstIndex(where: { $0.recording.id == recording.id }) {
            inner[i].isStoredLocally = true
        }
    }

    /// Pushes the current recordings (plain payload, no flags) to the
    /// cloud, then marks every local entry `isStoredRemotely = true`
    /// and persists. After this returns, every entry on this device
    /// is `isStoredLocally && isStoredRemotely`.
    func pushToRemote() async throws {
        try await cloud.set(inner.map { $0.recording })
        for i in inner.indices {
            inner[i].isStoredRemotely = true
        }
        save()
    }

    /// Fetches the cloud snapshot and adds any recordings the local
    /// `inner` doesn't already have, marking them `isStoredLocally ==
    /// false`, `isStoredRemotely == true`. Intentionally does NOT save
    /// to disk — a separate `persistToLocal()` call is required to
    /// commit the in-memory state. This asymmetry is what makes the
    /// "remote-only" intermediate state observable.
    func pullFromRemote() async throws {
        let remote = try await cloud.get()
        let localIDs = Set(inner.map { $0.recording.id })
        for r in remote where !localIDs.contains(r.id) {
            inner.append(StoredRecording(
                recording: r,
                isStoredLocally: false,
                isStoredRemotely: true
            ))
        }
    }

    /// Writes the in-memory `inner` to disk; if the write succeeds,
    /// every recording is marked `isStoredLocally = true`. The flag
    /// is earned by the actual disk write, not asserted before it.
    /// Intended to be called after `pullFromRemote()` to finalise
    /// newly-arrived recordings.
    func persistToLocal() async throws {
        guard save() else { return }
        for i in inner.indices {
            inner[i].isStoredLocally = true
        }
    }

    // MARK: - Database protocol methods (stubbed — green commits will fill them in)

    func appendChunk(_ chunk: AudioChunk, to recordingID: UUID) {
        guard let i = inner.firstIndex(where: { $0.recording.id == recordingID }) else { return }
        inner[i].recording.audioChunks.append(chunk)
        save()
    }

    func removeRecording(_ recordingID: UUID) {
        // Stub.
    }

    func markListened(recordingID: UUID, chunkIndex: Int) {
        // Stub.
    }

    func markListened(recordingID: UUID, chunkIndex: Int, by viewerID: UUID) {
        // Stub.
    }

    // MARK: - Private

    @discardableResult
    private func save() -> Bool {
        guard let data = try? JSONEncoder().encode(inner) else { return false }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
