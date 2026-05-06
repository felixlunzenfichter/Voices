import Foundation
import Network

/// Minimal in-process HTTP/1.1 responder for `RemoteDatabase` tests.
/// Listens on an OS-assigned loopback port; on each connection it
/// reads the request line + headers and replies with a single
/// `HTTP/1.1` response whose body comes from `respond`.
///
/// Not `@MainActor` — the response closure is called from a
/// `Network.framework` callback queue and stays simple/synchronous.
/// Tests treat the server as a black box: configure `respond` and
/// `bodyHandler` before `start()`, then poll `lastReceivedBody`
/// after the call under test.
final class FakeHTTPServer: @unchecked Sendable {
    private let lock = NSLock()
    private var _port: UInt16 = 0
    private var _lastReceivedBody: Data?
    private var listener: NWListener?

    /// Returns `(statusCode, responseBody)` for `(method, path)`.
    /// Default: 404. Set this before `start()`.
    var respond: (_ method: String, _ path: String) -> (Int, Data) = { _, _ in (404, Data()) }

    var port: UInt16 {
        lock.withLock { _port }
    }
    var lastReceivedBody: Data? {
        lock.withLock { _lastReceivedBody }
    }

    func start() async throws {
        let listener = try NWListener(using: .tcp)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] conn in
            self?.accept(conn)
        }
        listener.start(queue: .global())
        for _ in 0..<200 {
            if let raw = listener.port?.rawValue, raw > 0 {
                lock.withLock { _port = raw }
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw FakeHTTPServerError.portNotAssigned
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func accept(_ conn: NWConnection) {
        conn.start(queue: .global())
        receive(on: conn, accumulated: Data())
    }

    private func receive(on conn: NWConnection, accumulated: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = accumulated
            if let data { buffer.append(data) }
            if let parsed = parseRequest(buffer) {
                self.lock.withLock { self._lastReceivedBody = parsed.body }
                let (status, responseBody) = self.respond(parsed.method, parsed.path)
                let header = "HTTP/1.1 \(status) OK\r\nContent-Length: \(responseBody.count)\r\nContent-Type: application/json\r\nConnection: close\r\n\r\n"
                var response = Data(header.utf8)
                response.append(responseBody)
                conn.send(content: response, completion: .contentProcessed { _ in conn.cancel() })
                return
            }
            if error == nil && !isComplete {
                self.receive(on: conn, accumulated: buffer)
            } else {
                conn.cancel()
            }
        }
    }
}

private func parseRequest(_ data: Data) -> (method: String, path: String, body: Data)? {
    guard let separator = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
    let headerData = data.subdata(in: 0..<separator.lowerBound)
    guard let header = String(data: headerData, encoding: .utf8),
          let firstLine = header.split(separator: "\r\n").first else { return nil }
    let parts = firstLine.split(separator: " ")
    guard parts.count >= 2 else { return nil }
    let method = String(parts[0])
    let path = String(parts[1])
    let body = data.subdata(in: separator.upperBound..<data.count)
    if method == "POST" {
        // Wait for the full body if Content-Length says so.
        let lower = header.lowercased()
        if let lenRange = lower.range(of: "content-length:") {
            let restStart = header.index(header.startIndex, offsetBy: lower.distance(from: lower.startIndex, to: lenRange.upperBound))
            let rest = String(header[restStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
            let firstToken = rest.split(separator: "\r\n").first ?? Substring(rest)
            if let n = Int(firstToken.trimmingCharacters(in: .whitespaces)), body.count < n { return nil }
        }
    }
    return (method, path, body)
}

enum FakeHTTPServerError: Error { case portNotAssigned }
