import SwiftUI

struct VoicesView: View {
    @State private var harness = TwoPageHarness()

    var body: some View {
        TabView {
            ConversationPageView(vm: harness.mamaVM, title: "Mama")
            ConversationPageView(vm: harness.marinaVM, title: "Marina")
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(Color.black.ignoresSafeArea())
    }
}

/// Builds two VMs with distinct viewers and matching author-stamping
/// recording services, all sharing one local persistent `Database`.
/// Recordings survive app relaunch via `FileSystemDatabase` writing
/// to `Documents/voices/metadata.json`. No server, no launch args.
@MainActor
final class TwoPageHarness {
    let mamaVM: VoicesViewModel
    let marinaVM: VoicesViewModel

    static let mama   = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    static let marina = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    init() {
        let db: any Database
        do {
            db = try FileSystemDatabase()
        } catch {
            logError("TwoPageHarness: FileSystemDatabase init failed, falling back to in-memory: \(error)")
            db = InMemoryDatabase()
        }
        let totalChunks = db.recordings.reduce(0) { $0 + $1.audioChunks.count }
        log("TwoPageHarness: loaded \(db.recordings.count) recording(s), \(totalChunks) chunk(s)")

        mamaVM = VoicesViewModel(
            recordingService: DemoRecordingService(database: db, author: Self.mama, delay: .milliseconds(300)),
            playbackService: DemoPlaybackService(database: db, viewer: Self.mama, delay: .milliseconds(300)),
            database: db,
            viewer: Self.mama
        )

        marinaVM = VoicesViewModel(
            recordingService: DemoRecordingService(database: db, author: Self.marina, delay: .milliseconds(300)),
            playbackService: DemoPlaybackService(database: db, viewer: Self.marina, delay: .milliseconds(300)),
            database: db,
            viewer: Self.marina
        )
    }
}
