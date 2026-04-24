import Foundation
import UIKit

private let _deviceName: String = UIDevice.current.name

private let _logServerURL: URL = {
    var components = URLComponents()
    components.scheme = "ws"
    components.host = "felixs-macbook-pro.tailcfdca5.ts.net"
    components.port = 9998
    return components.url!
}()

private func _short(_ fileID: String) -> String {
    let name = fileID.components(separatedBy: "/").last ?? fileID
    return name.replacingOccurrences(of: ".swift", with: "")
}

// MARK: - Public API

@MainActor
func log(_ message: String, file: String = #fileID, function: String = #function) {
    _sendIngest(message, isError: false, file: file, function: function)
}

@MainActor
func logError(_ message: String, file: String = #fileID, function: String = #function) {
    _sendIngest(message, isError: true, file: file, function: function)
}

@MainActor
private func _sendIngest(_ message: String, isError: Bool, file: String, function: String) {
    let shortFile = _short(file)
    let payload: [String: Any] = [
        "device": _deviceName,
        "file": shortFile,
        "function": function,
        "message": message,
        "isError": isError
    ]

    guard let data = try? JSONSerialization.data(withJSONObject: payload),
          let json = String(data: data, encoding: .utf8) else { return }

    Task.detached {
        do {
            let ws = WSConnection()
            try await ws.connect(to: _logServerURL)
            defer { ws.close() }
            try await ws.send(json)
            _ = try await ws.receive()
        } catch {}
    }
}
