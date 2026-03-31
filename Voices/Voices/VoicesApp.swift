import SwiftUI
import UserNotifications

class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                              willPresent notification: UNNotification,
                              withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

@main
struct VoicesApp: App {
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    let notificationDelegate = NotificationDelegate()

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        UNUserNotificationCenter.current().delegate = notificationDelegate
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        Task { @MainActor in
            log("App launched")
        }
        return true
    }
}

func sendNotification(title: String = "Voices", body: String = "") {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = UNNotificationSound(named: UNNotificationSoundName("notification.caf"))

    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
    let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
    UNUserNotificationCenter.current().add(request)
}

// MARK: - Content View

struct ContentView: View {
    @State private var db = Database()
    @State private var chunkState = ChunkStateTracker()
    @State private var audio: AudioEngine?

    private var engine: AudioEngine { audio! }

    var body: some View {
        ZStack(alignment: .bottom) {
            if audio != nil {
                // Message list — each recording is a bubble with chunk bars
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .trailing, spacing: 12) {
                            ForEach(db.recordings) { recording in
                                messageRow(recording).id(recording.id)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 180)
                    }
                    .onChange(of: engine.currentlyPlayingChunkId) { _, newId in
                        if let newId,
                           let recording = db.recordings.first(where: { $0.chunks.contains { $0.id == newId } }) {
                            withAnimation { proxy.scrollTo(recording.id, anchor: .center) }
                        }
                    }
                }

                // Controls — play left, record right
                HStack {
                    ListenButton(
                        isListening: Binding(
                            get: { engine.isPlaying },
                            set: { $0 ? engine.startPlaying() : engine.stopPlaying() }
                        ),
                        nothingToPlay: !engine.hasPlayable
                    )
                    Spacer()
                    RecordButton(isRecording: Binding(
                        get: { engine.isRecording },
                        set: { newValue in
                            if newValue {
                                engine.startRecording()
                            } else {
                                engine.stopRecording()
                                sendNotification(title: "Recording", body: "Stopped")
                            }
                        }
                    ))
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 60)
            }
        }
        .onAppear {
            if audio == nil {
                audio = AudioEngine(db: db, chunkState: chunkState)
            }
        }
    }

    // Message bubble — chunks flow horizontally, wrap on overflow
    private func messageRow(_ recording: Recording) -> some View {
        FlowLayout(spacing: 2) {
            ForEach(recording.chunks) { chunk in
                RoundedRectangle(cornerRadius: 2)
                    .fill(chunkColor(chunkState.status(of: chunk.id)))
                    .frame(width: 6, height: 30)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }

    private func chunkColor(_ status: ChunkStatus) -> Color {
        switch status {
        case .recorded: .gray
        case .uploaded: .purple
        case .played:   .blue
        }
    }
}

// MARK: - Record Button

struct RecordButton: View {
    @Binding var isRecording: Bool

    private static let circleSize: CGFloat = 100
    private static let squareSize: CGFloat = circleSize / φ
    private static let cornerRadius: CGFloat = squareSize / pow(φ, 4)
    private static let animationDuration: CGFloat = 1 / φ
    private static let animationBounce: CGFloat = 1 - 1 / φ

    var body: some View {
        Button(action: {
            withAnimation(.spring(duration: Self.animationDuration, bounce: Self.animationBounce)) {
                isRecording.toggle()
            }
        }) {
            RoundedRectangle(cornerRadius: isRecording ? Self.cornerRadius : Self.circleSize / 2, style: .continuous)
                .fill(Color.red)
                .frame(width: isRecording ? Self.squareSize : Self.circleSize, height: isRecording ? Self.squareSize : Self.circleSize)
                .frame(width: Self.circleSize, height: Self.circleSize)
                .overlay(
                    Circle()
                        .stroke(Color.red, lineWidth: 1)
                        .frame(width: Self.circleSize, height: Self.circleSize)
                )
                .contentShape(Rectangle())
        }
    }
}

// MARK: - Listen Button

struct ListenButton: View {
    @Binding var isListening: Bool
    var nothingToPlay: Bool = false

    private static let size: CGFloat = 100

    var body: some View {
        Button(action: {
            isListening.toggle()
        }) {
            Image(systemName: isListening ? "pause.fill" : "play.fill")
                .font(.system(size: Self.size))
                .foregroundColor(nothingToPlay ? .purple : .blue)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: Self.size, height: Self.size)
        }
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 2

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Constants

let φ: CGFloat = (1 + sqrt(5)) / 2
