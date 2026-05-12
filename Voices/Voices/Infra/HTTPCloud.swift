import Foundation

/// `Cloud` conformer talking to the Mac-hosted voices-server over
/// real HTTP + Server-Sent Events.
///
/// `send` POSTs `/events` with `{ baseRevision, event }`. On 200 it
/// returns the server-assigned revision. On 409 it throws
/// `CloudConflictError` carrying the missed events the server
/// supplied so the caller can apply-and-retry.
///
/// `events(since:)` opens a long-lived stream against
/// `/events?since=N`, parses `data: { revision, event }` SSE frames,
/// and yields `(revision, event)` tuples. The stream finishes when
/// the underlying byte stream ends (transport drop, server close);
/// the caller can re-subscribe with the latest cursor.
@MainActor
final class HTTPCloud: Cloud {
    private let url: URL

    init(url: URL) {
        self.url = url
    }

    private struct SendOKResponse: Decodable {
        let revision: Int
    }

    private struct SendConflictResponse: Decodable {
        let revision: Int
        let events: [HistoryEntry]
    }

    private struct HistoryEntry: Decodable {
        let revision: Int
        let event: CloudEvent
    }

    private struct WirePayload<E: Encodable>: Encodable {
        let baseRevision: Int
        let event: E
    }

    func send(baseRevision: Int, event: CloudEvent) async throws -> Int {
        var request = URLRequest(url: url.appending(path: "events"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(WirePayload(baseRevision: baseRevision, event: event))
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        switch http.statusCode {
        case 200:
            let ok = try JSONDecoder().decode(SendOKResponse.self, from: data)
            return ok.revision
        case 409:
            let conflict = try JSONDecoder().decode(SendConflictResponse.self, from: data)
            throw CloudConflictError(
                currentRevision: conflict.revision,
                missedEvents: conflict.events.map { ($0.revision, $0.event) }
            )
        default:
            throw URLError(.badServerResponse)
        }
    }

    func events(since: Int) -> AsyncStream<(revision: Int, event: CloudEvent)> {
        let streamURL = url.appending(path: "events")
            .appending(queryItems: [URLQueryItem(name: "since", value: "\(since)")])
        return AsyncStream { continuation in
            let task = Task {
                do {
                    let (bytes, _) = try await URLSession.shared.bytes(from: streamURL)
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let json = String(line.dropFirst("data: ".count))
                        guard let payload = json.data(using: .utf8),
                              let entry = try? JSONDecoder().decode(HistoryEntry.self, from: payload)
                        else { continue }
                        continuation.yield((entry.revision, entry.event))
                    }
                } catch {
                    // Stream ended — transport error or cancellation.
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
