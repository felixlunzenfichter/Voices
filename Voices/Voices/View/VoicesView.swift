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
/// recording services, all sharing one `Database`. If the launch
/// argument `--server-url <url>` is supplied, both VMs talk to a
/// `RemoteDatabase` pointing at that URL (typically the Mac-hosted
/// `voices-server` reachable over Tailscale). Otherwise the harness
/// falls back to `InMemoryDatabase` so default builds and tests keep
/// working without any server running.
@MainActor
final class TwoPageHarness {
    let mamaVM: VoicesViewModel
    let marinaVM: VoicesViewModel

    static let mama   = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    static let marina = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    init() {
        let db: any Database = Self.makeDatabase()

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

        let totalChunks = db.recordings.reduce(0) { $0 + $1.audioChunks.count }
        log("TwoPageHarness: ready (\(db.recordings.count) recording(s), \(totalChunks) chunk(s))")
    }

    /// Resolves which `Database` to use based on launch arguments.
    /// If any launch argument is an `http(s)://...` URL, build a
    /// `RemoteDatabase` pointing at it. Otherwise fall back to
    /// `InMemoryDatabase` so default builds and tests keep working.
    /// (We scan for a URL rather than expecting `--server-url <url>`
    /// because `devicectl` passes the literal `--argument` token
    /// through to the process between every value.)
    private static func makeDatabase() -> any Database {
        let args = ProcessInfo.processInfo.arguments
        if let urlString = args.first(where: { $0.hasPrefix("http://") || $0.hasPrefix("https://") }),
           let url = URL(string: urlString) {
            log("TwoPageHarness: using RemoteDatabase at \(url.absoluteString)")
            return RemoteDatabase(baseURL: url)
        }
        log("TwoPageHarness: using InMemoryDatabase (no server URL in args)")
        return InMemoryDatabase()
    }
}
