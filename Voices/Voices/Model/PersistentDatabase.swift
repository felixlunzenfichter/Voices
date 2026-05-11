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
    /// Long-lived push channel. Each yield is the cloud's full
    /// `[Recording]` snapshot at some revision — sent on the first
    /// subscription (catch-up) and after every accepted POST /state.
    /// The stream ends on transport error or cancellation.
    func events() -> AsyncStream<[Recording]>
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
    private var subscriptionTask: Task<Void, Never>?

    init(localFileURL: URL, cloud: Cloud) {
        self.url = localFileURL
        self.cloud = cloud
        if let data = try? Data(contentsOf: localFileURL),
           let loaded = try? JSONDecoder().decode([StoredRecording].self, from: data) {
            self.inner = loaded
        } else {
            self.inner = []
        }
        self.subscriptionTask = nil
        self.subscriptionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await remote in self.cloud.events() {
                self.applyRemote(remote)
            }
        }
    }

    deinit {
        subscriptionTask?.cancel()
    }

    /// Folds a remote `[Recording]` snapshot into `inner`. New
    /// recordings arrive with `isStoredLocally == false`,
    /// `isStoredRemotely == true` (the same flag pattern
    /// `pullFromRemote()` uses). For recordings already known
    /// locally, `audioChunks` is per-index OR-merged on `listened`
    /// (`local || remote`) and extended to the longer of the two
    /// arrays. Flag fields on existing `StoredRecording`s are left
    /// untouched — local storage state is per-device.
    private func applyRemote(_ remote: [Recording]) {
        let localIDs = Set(inner.map { $0.recording.id })
        for r in remote where !localIDs.contains(r.id) {
            inner.append(StoredRecording(
                recording: r,
                isStoredLocally: false,
                isStoredRemotely: true
            ))
        }
        for i in inner.indices {
            guard let r = remote.first(where: { $0.id == inner[i].recording.id }) else { continue }
            let local = inner[i].recording.audioChunks
            let n = max(local.count, r.audioChunks.count)
            var merged: [AudioChunk] = []
            merged.reserveCapacity(n)
            for j in 0..<n {
                let l = j < local.count ? local[j] : nil
                let rc = j < r.audioChunks.count ? r.audioChunks[j] : nil
                if let l, let rc {
                    merged.append(AudioChunk(index: l.index, listened: l.listened || rc.listened))
                } else if let l {
                    merged.append(l)
                } else if let rc {
                    merged.append(rc)
                }
            }
            inner[i].recording.audioChunks = merged
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
    /// After a successful save the current snapshot is also written
    /// through to the cloud as a fire-and-forget Task.
    func addRecording(_ recording: Recording) {
        inner.append(StoredRecording(recording: recording))
        guard save() else { return }
        if let i = inner.firstIndex(where: { $0.recording.id == recording.id }) {
            inner[i].isStoredLocally = true
        }
        writeThroughToCloud()
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
        writeThroughToCloud()
    }

    func removeRecording(_ recordingID: UUID) {
        // Stub.
    }

    func markListened(recordingID: UUID, chunkIndex: Int) {
        // Stub.
    }

    /// Author-aware mark — mirrors `InMemoryDatabase`'s rule that a
    /// viewer who is the recording's own author cannot turn their own
    /// chunk listened. On a real flip we save locally and write the
    /// snapshot through to the cloud.
    func markListened(recordingID: UUID, chunkIndex: Int, by viewerID: UUID) {
        guard let i = inner.firstIndex(where: { $0.recording.id == recordingID }),
              inner[i].recording.author != viewerID,
              chunkIndex < inner[i].recording.audioChunks.count else { return }
        inner[i].recording.audioChunks[chunkIndex].listened = true
        save()
        writeThroughToCloud()
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

    /// Fire-and-forget snapshot push. Captures the current recordings
    /// synchronously, then POSTs from a detached Task so callers stay
    /// synchronous. No baseRevision yet, no conflict handling yet — a
    /// later step adds compare-and-swap against the server's cursor.
    private func writeThroughToCloud() {
        let snapshot = inner.map { $0.recording }
        Task { try? await cloud.set(snapshot) }
    }
}
