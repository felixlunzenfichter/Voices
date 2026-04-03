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
    @State private var isListening = false
    @State private var store = ChunkStore()
    @State private var chunkTimer: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            ChunkStrip(chunks: store.chunks, activeIndex: store.activeIndex)
                .padding(.bottom, 16)

            HStack {
                ListenButton(isListening: $isListening)
                Spacer()
                RecordButton(isRecording: $isRecording)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 60)
        }
        .onChange(of: isRecording) { _, newValue in
            if newValue {
                startRecording()
            } else {
                stopRecording()
            }
        }
        .onChange(of: isListening) { _, newValue in
            if newValue {
                startListening()
            } else {
                stopListening()
            }
        }
    }

    func startRecording() {
        log("Recording started")
        chunkTimer = Task {
            while !Task.isCancelled {
                store.appendRecorded()
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    func stopRecording() {
        chunkTimer?.cancel()
        chunkTimer = nil
        store.clearActive()
        log("Recording stopped")
        sendNotification(title: "Recording", body: "Stopped")
    }

    func startListening() {
        log("Listening started")
    }

    func stopListening() {
        log("Listening stopped")
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
    @Binding var isListening: Bool

    private static let size: CGFloat = 100

    var body: some View {
        Button(action: {
            isListening.toggle()
        }) {
            Image(systemName: isListening ? "pause.fill" : "play.fill")
                .font(.system(size: Self.size))
                .foregroundColor(.blue)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: Self.size, height: Self.size)
        }
    }
}

// MARK: - Constants

let φ: CGFloat = (1 + sqrt(5)) / 2

