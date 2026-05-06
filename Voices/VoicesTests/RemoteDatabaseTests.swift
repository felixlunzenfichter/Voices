import Foundation
import Observation
import Testing
@testable import Voices

@MainActor
struct RemoteDatabaseTests {

    /// Round-trip through the wire: `RemoteDatabase` polls `GET /state`,
    /// the fake server returns a canned snapshot, the database mirrors
    /// the recordings into its observable property. The contract this
    /// pins is "remote state arrives, local UI sees it" — the read
    /// half of the seam.
    @Test("RemoteDatabase mirrors a server snapshot into observable recordings",
          .timeLimit(.minutes(1)))
    func mirrorsServerSnapshot() async throws {
        let server = FakeHTTPServer()
        let recID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let author = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let body = """
        {"recordings":[{"id":"\(recID.uuidString)","author":"\(author.uuidString)","audioChunks":[{"index":0,"listened":false}]}]}
        """
        let bodyData = Data(body.utf8)
        server.respond = { method, path in
            (method == "GET" && path == "/state") ? (200, bodyData) : (404, Data())
        }
        try await server.start()

        let url = URL(string: "http://127.0.0.1:\(server.port)")!
        let db = RemoteDatabase(baseURL: url, pollInterval: .milliseconds(50))

        for await count in Observations({ db.recordings.count }) {
            if count > 0 { break }
        }

        #expect(db.recordings.first?.id == recID)
        #expect(db.recordings.first?.author == author)
        #expect(db.recordings.first?.audioChunks.first?.index == 0)
        server.stop()
    }
}
