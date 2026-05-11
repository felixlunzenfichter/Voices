import Foundation
import Network
@testable import Voices

/// In-process HTTP/1.1 server for the cloud round-trip tests. Listens
/// on an OS-assigned `127.0.0.1` port and serves the snapshot Cloud
/// protocol:
///
///   GET  /state  →  200, body = JSONEncoder().encode(stored)
///   POST /state  →  200, side effect: stored = JSON-decoded body
///
/// Not `@MainActor`. Network.framework hands callbacks back on a
/// global queue; the in-memory snapshot is guarded by an `NSLock`.
/// One server per test: `start()` in arrange, `stop()` in defer.
final class Server: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Recording] = []
    private var listener: NWListener?
    private var _port: UInt16 = 0

    var port: UInt16 { lock.withLock { _port } }
    var url: URL { URL(string: "http://127.0.0.1:\(port)")! }

    static func start() async throws -> Server {
        let s = Server()
        try await s.run()
        return s
    }

    private func run() async throws {
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
        throw NSError(domain: "Server", code: -1, userInfo: [NSLocalizedDescriptionKey: "Listener never bound"])
    }

    func stop() async {
        listener?.cancel()
        listener = nil
    }

    private func accept(_ conn: NWConnection) {
        conn.start(queue: .global())
        receive(on: conn, accumulated: Data())
    }

    private func receive(on conn: NWConnection, accumulated: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            var buf = accumulated
            if let data = data { buf.append(data) }
            if let request = self.parseIfComplete(buf) {
                self.handle(request, on: conn)
                return
            }
            if isComplete || error != nil {
                conn.cancel()
                return
            }
            self.receive(on: conn, accumulated: buf)
        }
    }

    private func parseIfComplete(_ data: Data) -> (method: String, path: String, body: Data)? {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headers = data.subdata(in: 0..<headerEnd.lowerBound)
        guard let headerStr = String(data: headers, encoding: .utf8) else { return nil }
        let lines = headerStr.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2 else { return nil }
        let method = String(parts[0])
        let path = String(parts[1])

        var contentLength = 0
        for line in lines.dropFirst() {
            let lower = line.lowercased()
            if lower.hasPrefix("content-length:") {
                let value = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                contentLength = Int(value) ?? 0
            }
        }

        let bodyStart = headerEnd.upperBound
        let received = data.count - bodyStart
        if received < contentLength { return nil }
        let body = data.subdata(in: bodyStart..<(bodyStart + contentLength))
        return (method, path, body)
    }

    private func handle(_ request: (method: String, path: String, body: Data), on conn: NWConnection) {
        let status: Int
        let body: Data
        switch (request.method, request.path) {
        case ("GET", "/state"):
            let snapshot: [Recording] = lock.withLock { stored }
            body = (try? JSONEncoder().encode(snapshot)) ?? Data("[]".utf8)
            status = 200
        case ("POST", "/state"):
            if let decoded = try? JSONDecoder().decode([Recording].self, from: request.body) {
                lock.withLock { stored = decoded }
                body = Data()
                status = 200
            } else {
                body = Data()
                status = 400
            }
        default:
            body = Data()
            status = 404
        }
        send(status: status, body: body, on: conn)
    }

    private func send(status: Int, body: Data, on conn: NWConnection) {
        let reason = (status == 200) ? "OK" : (status == 404 ? "Not Found" : "Bad Request")
        let header = "HTTP/1.1 \(status) \(reason)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        var response = Data(header.utf8)
        response.append(body)
        conn.send(content: response, completion: .contentProcessed { _ in
            conn.cancel()
        })
    }
}
