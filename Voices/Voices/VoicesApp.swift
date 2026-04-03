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

struct ContentView: View {
    @State private var isRecording = false
    @State private var store = ChunkStore()
    @State private var chunkTimer: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            MessageList(recordings: store.recordings)

            if isRecording || store.hasListenable {
                ChunkStrip(chunks: store.currentChunks, activeIndex: store.activeIndex)
                    .padding(.bottom, 16)
            }

            HStack {
                ListenButton(
                    isListening: store.isListening,
                    hasListenable: store.hasListenable,
                    onTap: { toggleListening() }
                )
                Spacer()
                RecordButton(isRecording: $isRecording)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 60)
        }
        .onChange(of: isRecording) { _, newValue in
            if newValue {
                if store.isListening { store.stopListening() }
                startRecording()
            } else {
                stopRecording()
            }
        }
    }

    func toggleListening() {
        if store.isListening {
            store.stopListening()
        } else {
            if isRecording {
                withAnimation(.spring(duration: 1/φ, bounce: 1 - 1/φ)) {
                    isRecording = false
                }
            }
            store.startListening()
        }
    }

    func startRecording() {
        log("Recording started")
        store.startRecording()
        chunkTimer = Task {
            while !Task.isCancelled {
                store.appendChunk()
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    func stopRecording() {
        chunkTimer?.cancel()
        chunkTimer = nil
        store.stopRecording()
        log("Recording stopped")
        sendNotification(title: "Recording", body: "Stopped")
    }
}

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

struct ListenButton: View {
    let isListening: Bool
    let hasListenable: Bool
    let onTap: () -> Void

    private static let size: CGFloat = 100

    private var icon: String { (isListening || !hasListenable) ? "pause.fill" : "play.fill" }
    private var tint: Color { hasListenable ? .blue : .purple }

    var body: some View {
        Button(action: onTap) {
            Image(systemName: icon)
                .font(.system(size: Self.size))
                .foregroundColor(tint)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: Self.size, height: Self.size)
        }
        .disabled(!isListening && !hasListenable)
    }
}

// MARK: - Constants

let φ: CGFloat = (1 + sqrt(5)) / 2

