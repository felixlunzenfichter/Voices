import SwiftUI

struct VoicesView: View {
    @State private var harness = TwoPageHarness()
    @State private var didAutoStart = false

    var body: some View {
        TabView {
            ConversationPageView(vm: harness.mamaVM, title: "Mama")
            ConversationPageView(vm: harness.marinaVM, title: "Marina")
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            guard !didAutoStart, !isRunningUnderTest else { return }
            didAutoStart = true
            harness.mamaVM.toggleRecording()
            harness.marinaVM.toggleRecording()
        }
    }
}

private var isRunningUnderTest: Bool {
    ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
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
        let mamaDB = FirebaseDatabase(viewer: Self.mama)
        let marinaDB = FirebaseDatabase(viewer: Self.marina)

        mamaVM = VoicesViewModel(
            recordingService: DemoRecordingService(database: mamaDB, author: Self.mama, delay: .milliseconds(300)),
            playbackService: DemoPlaybackService(database: mamaDB, viewer: Self.mama, delay: .milliseconds(300)),
            database: mamaDB,
            viewer: Self.mama
        )

        marinaVM = VoicesViewModel(
            recordingService: DemoRecordingService(database: marinaDB, author: Self.marina, delay: .milliseconds(300)),
            playbackService: DemoPlaybackService(database: marinaDB, viewer: Self.marina, delay: .milliseconds(300)),
            database: marinaDB,
            viewer: Self.marina
        )
    }
}
