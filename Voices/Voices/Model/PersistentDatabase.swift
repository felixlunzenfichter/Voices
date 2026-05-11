import Foundation
import Observation

/// Source-of-truth bridge between local app state and the cloud's
/// append-only event history.
///
/// Owns three pieces of state, persisted together to one JSON file:
///   • `recordings`  — projection of applied events.
///   • `cursor`      — highest revision seen and applied; the CAS base
///                     used on the next outbound write.
///   • `outbound`    — events composed locally but not yet acknowledged
///                     by the cloud. Survives reconnect and relaunch.
///
/// Spawns two long-lived Tasks at init:
///   • subscriber — `for await (r, e) in cloud.events(since: cursor)`,
///                  feeds each into `applyEvent`. This is the read path.
///   • drainer    — pumps the head of `outbound` through `cloud.send`,
///                  handling 200 (pop + advance cursor), 409 (apply
///                  missed events, retry head), and transport error
///                  (back off, retry). This is the write path.
///
/// Local mutations apply optimistically before the send, so the UI is
/// snappy. Idempotent apply makes own-echo and retry no-ops.
@Observable @MainActor
final class PersistentDatabase: Database {
    private(set) var recordings: [Recording] = []
    @ObservationIgnored private var cursor: Int = 0
    @ObservationIgnored private var outbound: [CloudEvent] = []
    @ObservationIgnored private var online: Bool
    @ObservationIgnored private let url: URL
    @ObservationIgnored private let cloud: Cloud
    @ObservationIgnored private var subscriptionTask: Task<Void, Never>?
    @ObservationIgnored private var drainerTask: Task<Void, Never>?

    init(localFileURL: URL, cloud: Cloud, online: Bool = true) {
        self.url = localFileURL
        self.cloud = cloud
        self.online = online
        load()
        subscriptionTask = nil
        drainerTask = nil
        if online {
            subscriptionTask = makeSubscriptionTask()
        }
        drainerTask = Task { @MainActor [weak self] in
            await self?.drain()
        }
    }

    deinit {
        subscriptionTask?.cancel()
        drainerTask?.cancel()
    }

    /// Pauses or resumes cloud-facing background work. While `online`
    /// is `false`, the drainer parks the outbound queue (writes still
    /// apply locally and accumulate) and the subscriber stream is
    /// torn down so this instance receives no remote events. When
    /// flipped back to `true`, the drainer resumes pumping and a
    /// fresh subscriber stream opens with `since: cursor`, replaying
    /// anything missed.
    func setOnline(_ value: Bool) {
        guard online != value else { return }
        online = value
        if value {
            subscriptionTask = makeSubscriptionTask()
        } else {
            subscriptionTask?.cancel()
            subscriptionTask = nil
        }
    }

    private func makeSubscriptionTask() -> Task<Void, Never> {
        Task { @MainActor [weak self] in
            guard let self else { return }
            for await (revision, event) in self.cloud.events(since: self.cursor) {
                self.applyEvent(event, revision: revision)
            }
        }
    }

    // MARK: - Database protocol

    func addRecording(_ recording: Recording) {
        emit(.recordingAdded(recording))
    }

    func appendChunk(_ chunk: AudioChunk, to recordingID: UUID) {
        emit(.chunkAppended(recordingID: recordingID, chunk: chunk))
    }

    func removeRecording(_ recordingID: UUID) {
        // Not yet part of the event vocabulary.
    }

    func markListened(recordingID: UUID, chunkIndex: Int) {
        // Author-blind variant — unused by the current playback path.
    }

    func markListened(recordingID: UUID, chunkIndex: Int, by viewerID: UUID) {
        // Author guard: a viewer who is the recording's own author
        // cannot mark their own chunk listened.
        guard let i = recordings.firstIndex(where: { $0.id == recordingID }),
              recordings[i].author != viewerID,
              chunkIndex < recordings[i].audioChunks.count else { return }
        emit(.chunkListened(recordingID: recordingID, chunkIndex: chunkIndex, by: viewerID))
    }

    // MARK: - Local emit

    private func emit(_ event: CloudEvent) {
        applyEventLocally(event)
        outbound.append(event)
        save()
    }

    // MARK: - Apply

    /// Called from the subscriber Task when the cloud delivers an event.
    /// Advances the cursor and persists.
    private func applyEvent(_ event: CloudEvent, revision: Int) {
        applyEventLocally(event)
        cursor = max(cursor, revision)
        save()
    }

    /// Idempotent fold. Re-applying an already-applied event leaves
    /// `recordings` unchanged.
    private func applyEventLocally(_ event: CloudEvent) {
        switch event {
        case .recordingAdded(let recording):
            if !recordings.contains(where: { $0.id == recording.id }) {
                recordings.append(recording)
            }
        case .chunkAppended(let id, let chunk):
            guard let i = recordings.firstIndex(where: { $0.id == id }) else { return }
            if !recordings[i].audioChunks.contains(where: { $0.index == chunk.index }) {
                recordings[i].audioChunks.append(chunk)
            }
        case .chunkListened(let id, let chunkIndex, let viewer):
            guard let i = recordings.firstIndex(where: { $0.id == id }),
                  recordings[i].author != viewer,
                  let j = recordings[i].audioChunks.firstIndex(where: { $0.index == chunkIndex }) else { return }
            recordings[i].audioChunks[j].listened = true
        }
    }

    // MARK: - Drain

    /// Pumps `outbound` head into `cloud.send`. Runs until cancelled.
    /// Polls a short interval while the queue is empty.
    private func drain() async {
        while !Task.isCancelled {
            guard online else {
                try? await Task.sleep(for: .milliseconds(50))
                continue
            }
            guard let head = outbound.first else {
                try? await Task.sleep(for: .milliseconds(50))
                continue
            }
            do {
                let acceptedAt = try await cloud.send(baseRevision: cursor, event: head)
                cursor = max(cursor, acceptedAt)
                if !outbound.isEmpty { outbound.removeFirst() }
                save()
            } catch let conflict as CloudConflictError {
                for (revision, event) in conflict.missedEvents {
                    applyEvent(event, revision: revision)
                }
                // Retry head on the next loop iteration with the bumped cursor.
            } catch {
                // Transport error — back off and try again.
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    // MARK: - Persistence

    private struct OnDisk: Codable {
        var cursor: Int
        var recordings: [Recording]
        var outbound: [CloudEvent]
    }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(OnDisk.self, from: data) else { return }
        self.cursor = decoded.cursor
        self.recordings = decoded.recordings
        self.outbound = decoded.outbound
    }

    @discardableResult
    private func save() -> Bool {
        let snapshot = OnDisk(cursor: cursor, recordings: recordings, outbound: outbound)
        guard let data = try? JSONEncoder().encode(snapshot) else { return false }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}

// MARK: - Cloud protocol

/// Cloud is the source of truth. Clients sync by asking for the
/// event diff since their last seen revision, and write by CAS
/// against that same cursor.
@MainActor
protocol Cloud: AnyObject {
    /// Submit one event with a CAS precondition. Returns the
    /// server-assigned revision on accept. Throws `CloudConflictError`
    /// with the missed events when `baseRevision < server.revision`.
    /// May throw transport errors; the caller retries.
    func send(baseRevision: Int, event: CloudEvent) async throws -> Int

    /// Subscribe to the event history beginning *after* the given
    /// revision. The stream first replays every (revision, event)
    /// with `revision > since`, then continues live.
    func events(since: Int) -> AsyncStream<(revision: Int, event: CloudEvent)>
}

struct CloudConflictError: Error {
    let currentRevision: Int
    let missedEvents: [(revision: Int, event: CloudEvent)]
}
