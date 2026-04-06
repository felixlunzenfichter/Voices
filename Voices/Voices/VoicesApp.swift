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
    @State private var vm = VoicesViewModel()

    var body: some View {
        VStack(spacing: 0) {
            ChunkBarStrip(chunks: vm.store.allChunks, activeIndex: vm.store.activeIndex)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .task {
                    #if DEBUG
                    await vm.selfTest()
                    #endif
                }

            HStack {
                ListenButton(isListening: vm.isListening, hasListenable: vm.store.hasListenable, onTap: { vm.toggleListening() })
                Spacer()
                RecordButton(isRecording: vm.isRecording, onTap: { vm.toggleRecording() })
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 60)
        }
    }
}

struct RecordButton: View {
    let isRecording: Bool
    let onTap: () -> Void

    private static let circleSize: CGFloat = 100
    private static let squareSize: CGFloat = circleSize / φ
    private static let cornerRadius: CGFloat = squareSize / pow(φ, 4)

    private static let animationDuration: CGFloat = 1 / φ
    private static let animationBounce: CGFloat = 1 - 1 / φ

    var body: some View {
        Button(action: {
            withAnimation(.spring(duration: Self.animationDuration, bounce: Self.animationBounce)) {
                onTap()
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
    private var tint: Color { hasListenable ? .blue : .purple }

    var body: some View {
        Button(action: {
            onTap()
        }) {
            Image(systemName: (isListening || !hasListenable) ? "pause.fill" : "play.fill")
                .font(.system(size: Self.size))
                .foregroundColor(tint)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: Self.size, height: Self.size)
        }
    }
}

struct ChunkBarStrip: View {
    let chunks: [ChunkEntry]
    var activeIndex: Int?

    static let barWidth: CGFloat = 6
    static let barHeight: CGFloat = 30
    static let gap: CGFloat = 2
    static let step: CGFloat = barWidth + gap

    var body: some View {
        GeometryReader { geo in
            let center = geo.size.width / 2
            let target = activeIndex ?? max(chunks.count - 1, 0)
            let offset = center - CGFloat(target) * Self.step

            HStack(spacing: Self.gap) {
                ForEach(chunks) { chunk in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(chunk.status.color)
                        .frame(width: Self.barWidth, height: Self.barHeight)
                }
            }
            .offset(x: offset)
            #if DEBUG
            .onChange(of: chunks.count) {
                if let idx = activeIndex {
                    let barPosition = offset + CGFloat(idx) * Self.step
                    let diff = abs(barPosition - center)
                    if diff > 1 {
                        logError("TEST FAIL: bar strip not centered — active bar at \(Int(barPosition))px, center at \(Int(center))px, diff \(Int(diff))px")
                    }
                }
            }
            .onChange(of: activeIndex) {
                if let idx = activeIndex {
                    let barPosition = offset + CGFloat(idx) * Self.step
                    let diff = abs(barPosition - center)
                    if diff > 1 {
                        logError("TEST FAIL: bar strip not centered — active bar at \(Int(barPosition))px, center at \(Int(center))px, diff \(Int(diff))px")
                    }
                }
            }
            #endif
        }
        .frame(height: Self.barHeight)
    }
}

// MARK: - Constants

let φ: CGFloat = (1 + sqrt(5)) / 2

