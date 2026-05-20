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
/// recording services, each over its own FirebaseDatabase pointing at
/// the same shared emulator. Two devices running this harness reach
/// each other's recordings through that shared Firestore collection.
@MainActor
final class TwoPageHarness {
    let mamaVM: VoicesViewModel
    let marinaVM: VoicesViewModel

    static let mama   = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    static let marina = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    init() {
#if canImport(FirebaseCore)
        let db: any Database = FirebaseDatabase()
#else
        let db: any Database = InMemoryDatabase()
#endif

        mamaVM = VoicesViewModel(
            recordingService: RealRecordingService(database: db, author: Self.mama),
            playbackService: RealPlaybackService(database: db, viewer: Self.mama),
            database: db,
            viewer: Self.mama
        )

        marinaVM = VoicesViewModel(
            recordingService: RealRecordingService(database: db, author: Self.marina),
            playbackService: RealPlaybackService(database: db, viewer: Self.marina),
            database: db,
            viewer: Self.marina
        )
    }
}
