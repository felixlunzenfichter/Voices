import Foundation
import Observation

/// `Database` implementation that talks to a remote voices-server.
/// Polls `GET /state` on a timer and mirrors the response into the
/// observable `recordings` array; sends mutations as `POST /mutation`
/// JSON. The server is the source of truth — mutators don't apply
/// locally, they post and rely on the next poll for the UI to catch
/// up.
///
/// Polling cadence is 500 ms by default; tune via `pollInterval` for
/// tests. No reconnect logic, no retries beyond "swallow and try
/// again next tick" — fine for v1, hardened later.
@Observable @MainActor
final class RemoteDatabase: Database {
    private(set) var recordings: [Recording] = []

    @ObservationIgnored
    private let baseURL: URL
    @ObservationIgnored
    private let session: URLSession

    nonisolated init(baseURL: URL, pollInterval: Duration = .milliseconds(500)) {
        self.baseURL = baseURL
        self.session = URLSession(configuration: .default)
        Task { @MainActor [self] in
            await pollLoop(interval: pollInterval)
        }
    }

    // MARK: - Database (mutators) — POST one of `Mutation`

    func addRecording(_ recording: Recording) {
        post(MutationEnvelope.addRecording(recording: recording))
    }

    func appendChunk(_ chunk: AudioChunk, to recordingID: UUID) {
        post(MutationEnvelope.appendChunk(recordingID: recordingID, chunk: chunk))
    }

    func removeRecording(_ recordingID: UUID) {
        post(MutationEnvelope.removeRecording(recordingID: recordingID))
    }

    func markListened(recordingID: UUID, chunkIndex: Int) {
        post(MutationEnvelope.markListened(recordingID: recordingID, chunkIndex: chunkIndex, by: nil))
    }

    func markListened(recordingID: UUID, chunkIndex: Int, by viewerID: UUID) {
        post(MutationEnvelope.markListened(recordingID: recordingID, chunkIndex: chunkIndex, by: viewerID))
    }

    // MARK: - Wire

    private func pollLoop(interval: Duration) async {
        var lastLoggedCount = -1
        while true {
            if let snapshot = await fetchState() {
                self.recordings = snapshot.recordings
                if snapshot.recordings.count != lastLoggedCount {
                    log("RemoteDatabase: poll → \(snapshot.recordings.count) recording(s)")
                    lastLoggedCount = snapshot.recordings.count
                }
            }
            try? await Task.sleep(for: interval)
        }
    }

    private func fetchState() async -> State? {
        let url = baseURL.appending(path: "state")
        do {
            let (data, _) = try await session.data(from: url)
            return try JSONDecoder().decode(State.self, from: data)
        } catch {
            // Swallow; next tick retries.
            return nil
        }
    }

    private func post(_ envelope: MutationEnvelope) {
        guard let body = try? JSONEncoder().encode(envelope) else { return }
        var req = URLRequest(url: baseURL.appending(path: "mutation"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        session.uploadTask(with: req, from: body).resume()
    }
}

// MARK: - Wire types

private struct State: Decodable {
    let recordings: [Recording]
}

/// Tagged-union encoding that matches the server's `Mutation` type.
private struct MutationEnvelope: Encodable {
    let type: String
    let recording: Recording?
    let recordingID: UUID?
    let chunk: AudioChunk?
    let chunkIndex: Int?
    let by: UUID?

    static func addRecording(recording: Recording) -> Self {
        Self(type: "addRecording", recording: recording, recordingID: nil, chunk: nil, chunkIndex: nil, by: nil)
    }
    static func appendChunk(recordingID: UUID, chunk: AudioChunk) -> Self {
        Self(type: "appendChunk", recording: nil, recordingID: recordingID, chunk: chunk, chunkIndex: nil, by: nil)
    }
    static func removeRecording(recordingID: UUID) -> Self {
        Self(type: "removeRecording", recording: nil, recordingID: recordingID, chunk: nil, chunkIndex: nil, by: nil)
    }
    static func markListened(recordingID: UUID, chunkIndex: Int, by: UUID?) -> Self {
        Self(type: "markListened", recording: nil, recordingID: recordingID, chunk: nil, chunkIndex: chunkIndex, by: by)
    }

    enum CodingKeys: String, CodingKey {
        case type, recording, recordingID, chunk, chunkIndex, by
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(type, forKey: .type)
        if let recording { try c.encode(recording, forKey: .recording) }
        if let recordingID { try c.encode(recordingID.uuidString, forKey: .recordingID) }
        if let chunk { try c.encode(chunk, forKey: .chunk) }
        if let chunkIndex { try c.encode(chunkIndex, forKey: .chunkIndex) }
        if let by { try c.encode(by.uuidString, forKey: .by) }
    }
}
