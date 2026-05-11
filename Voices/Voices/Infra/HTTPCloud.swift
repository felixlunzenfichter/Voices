import Foundation

/// `Cloud` conformer that speaks the snapshot protocol over HTTP:
///
///   GET  {base}/state  →  `[Recording]` as JSON
///   POST {base}/state  →  request body = `[Recording]` as JSON
///
/// Pairs with the in-process `Server` fixture in `VoicesTests/` today;
/// the same conformer will point at a real Mac-hosted process later
/// without changing `PersistentDatabase`.
@MainActor
final class HTTPCloud: Cloud {
    private let url: URL

    init(url: URL) {
        self.url = url
    }

    func get() async throws -> [Recording] {
        let stateURL = url.appending(path: "state")
        let (data, _) = try await URLSession.shared.data(from: stateURL)
        return try JSONDecoder().decode([Recording].self, from: data)
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
