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
            MessageList(recordings: vm.store.recordings)
                .task {
                    #if DEBUG
                    await vm.selfTest()
                    #endif
                }

            ChunkBarStrip(
                chunks: vm.store.allChunks,
                activeIndex: vm.store.activeIndex,
                onScrub: { index in vm.scrubTo(index) }
            )
                .padding(.bottom, 16)

            HStack {
                ListenButton(isListening: vm.isListening, hasFreshContent: vm.store.hasListenable && !vm.store.allHeard, onTap: { vm.toggleListening() })
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
    let hasFreshContent: Bool
    let onTap: () -> Void

    private static let size: CGFloat = 100
    private var tint: Color { hasFreshContent ? .blue : .purple }

    var body: some View {
        Button(action: {
            onTap()
        }) {
            Image(systemName: (isListening || !hasFreshContent) ? "pause.fill" : "play.fill")
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
    var onScrub: ((Int) -> Void)?

    static let barWidth: CGFloat = 6
    static let barHeight: CGFloat = 30
    static let gap: CGFloat = 2
    static let step: CGFloat = barWidth + gap

    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false

    var body: some View {
        GeometryReader { geo in
            let center = geo.size.width / 2
            let target = activeIndex ?? max(chunks.count - 1, 0)
            let baseOffset = center - CGFloat(target) * Self.step
            let effectiveOffset = isDragging ? baseOffset + dragOffset : baseOffset

            HStack(spacing: Self.gap) {
                ForEach(chunks) { chunk in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(chunk.status.color)
                        .frame(width: Self.barWidth, height: Self.barHeight)
                }
            }
            .offset(x: effectiveOffset)
            .gesture(chunks.isEmpty || onScrub == nil ? nil :
                DragGesture()
                    .onChanged { value in
                        isDragging = true
                        dragOffset = value.translation.width
                    }
                    .onEnded { value in
                        let idx = Int(round((center - baseOffset - value.translation.width) / Self.step))
                        let clamped = max(0, min(chunks.count - 1, idx))
                        dragOffset = 0
                        isDragging = false
                        onScrub?(clamped)
                    }
            )
            #if DEBUG
            .onChange(of: chunks.count) {
                if let idx = activeIndex {
                    let barPosition = baseOffset + CGFloat(idx) * Self.step
                    let diff = abs(barPosition - center)
                    if diff > 1 {
                        logError("TEST FAIL: bar strip not centered — active bar at \(Int(barPosition))px, center at \(Int(center))px, diff \(Int(diff))px")
                    }
                }
            }
            .onChange(of: activeIndex) {
                if let idx = activeIndex {
                    let barPosition = baseOffset + CGFloat(idx) * Self.step
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

// MARK: - Message list

struct MessageList: View {
    let recordings: [Recording]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(recordings) { recording in
                        MessageBubble(recording: recording)
                            .id(recording.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .onChange(of: recordings.last?.chunks.count) {
                if let id = recordings.last?.id {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(id, anchor: .bottom)
                    }
                }
            }
        }
    }
}

private struct MessageBubble: View {
    let recording: Recording

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(recording.createdAt, style: .time)
                .font(.caption2)
                .foregroundStyle(.secondary)

            FlowLayout(spacing: 2) {
                ForEach(recording.chunks) { chunk in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(chunk.status.color)
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
    }
}

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

