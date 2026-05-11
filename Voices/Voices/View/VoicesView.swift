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
/// recording services, all sharing one `PersistentDatabase` wired to
/// the Mac-hosted voices-server. Local state on disk; cross-device
/// propagation through HTTPCloud (POST /state) + SSE (/events). The
/// mama and marina UUIDs are stable across devices, so the two pages
/// on phone A talk to the same conceptual mama and marina that
/// phone B is talking to.
@MainActor
final class TwoPageHarness {
    let mamaVM: VoicesViewModel
    let marinaVM: VoicesViewModel

    static let mama   = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    static let marina = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    init() {
        let url = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask).first!
            .appending(path: "voices-state.json")
        let cloud = HTTPCloud(url: URL(string: "http://felixs-macbook-pro.tailcfdca5.ts.net:9995")!)
        let db = PersistentDatabase(localFileURL: url, cloud: cloud)

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
