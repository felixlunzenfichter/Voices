import Foundation

/// Shared remote store. Each method is a full-snapshot exchange — no
/// deltas, no per-record CRUD. The single conformer in the scratch is
/// `InMemoryCloud` in the test target; a real `MacServerCloud` (or
/// equivalent) is a later concern.
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
final class PersistentDatabase {
    private let url: URL
    private let cloud: Cloud
    private var inner: [Recording]

    init(localFileURL: URL, cloud: Cloud) {
        self.url = localFileURL
        self.cloud = cloud
        if let data = try? Data(contentsOf: localFileURL),
           let loaded = try? JSONDecoder().decode([Recording].self, from: data) {
            self.inner = loaded
        } else {
            self.inner = []
        }
    }

    var recordings: [Recording] { inner }

    // MARK: - Lifecycle methods that drive flag transitions

    /// Adds a recording locally. The new recording is `isStoredLocally
    /// == true`, `isStoredRemotely == false`. Persists to disk
    /// synchronously.
    func addRecording(_ recording: Recording) {
        var rec = recording
        rec.isStoredLocally = true
        rec.isStoredRemotely = false
        inner.append(rec)
        save()
    }

    /// Pushes the current `inner` to the cloud, then marks every local
    /// recording `isStoredRemotely = true` and persists. After this
    /// returns, every recording on this device is `isStoredLocally &&
    /// isStoredRemotely`.
    func pushToRemote() async throws {
        try await cloud.set(inner)
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
        let localIDs = Set(inner.map { $0.id })
        for r in remote where !localIDs.contains(r.id) {
            var rec = r
            rec.isStoredLocally = false
            rec.isStoredRemotely = true
            inner.append(rec)
        }
    }

    /// Writes the in-memory `inner` to disk and marks every recording
    /// `isStoredLocally = true`. Intended to be called after
    /// `pullFromRemote()` to finalise newly-arrived recordings.
    func persistToLocal() async throws {
        for i in inner.indices {
            inner[i].isStoredLocally = true
        }
        save()
    }

    // MARK: - Private

    private func save() {
        guard let data = try? JSONEncoder().encode(inner) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
