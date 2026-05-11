import Foundation

/// `Cloud` conformer that speaks the snapshot protocol over HTTP:
///
///   GET  {base}/state  →  `{ revision, recordings }` as JSON
///   POST {base}/state  →  request body = `[Recording]`,
///                          response body = `{ revision }`
///
/// `revision` is the server's monotonically increasing write cursor.
/// It is read off the wire so this conformer can later carry it as a
/// `baseRevision` on writes, but for now it is not yet exposed to
/// callers — `get()` still returns just `[Recording]`.
@MainActor
final class HTTPCloud: Cloud {
    private let url: URL

    init(url: URL) {
        self.url = url
    }

    private struct StateResponse: Codable {
        let revision: Int
        let recordings: [Recording]
    }

    func get() async throws -> [Recording] {
        let stateURL = url.appending(path: "state")
        let (data, _) = try await URLSession.shared.data(from: stateURL)
        let response = try JSONDecoder().decode(StateResponse.self, from: data)
        return response.recordings
    }

    func set(_ recordings: [Recording]) async throws {
        let stateURL = url.appending(path: "state")
        var request = URLRequest(url: stateURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(recordings)
        _ = try await URLSession.shared.data(for: request)
    }
}
