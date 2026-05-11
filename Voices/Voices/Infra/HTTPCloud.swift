import Foundation

/// `Cloud` conformer talking to the Mac-hosted voices-server.
/// Stage 2 stub — `send` throws "not implemented" and `events`
/// yields nothing. Replaced in Stage 4 with real URLSession-backed
/// HTTP/SSE.
@MainActor
final class HTTPCloud: Cloud {
    private let url: URL

    init(url: URL) {
        self.url = url
    }

    func send(baseRevision: Int, event: CloudEvent) async throws -> Int {
        throw NSError(domain: "HTTPCloud", code: -1, userInfo: [
            NSLocalizedDescriptionKey: "HTTPCloud.send not yet implemented"
        ])
    }

    func events(since: Int) -> AsyncStream<(revision: Int, event: CloudEvent)> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}
