import SwiftUI

struct ContentView: View {
    @State private var vm: VoicesViewModel = {
        let db = InMemoryDatabase()
        return VoicesViewModel(
            recordingService: DemoRecordingService(database: db, delay: .milliseconds(300)),
            playbackService: DemoPlaybackService(database: db, delay: .milliseconds(300)),
            database: db
        )
    }()
    @State private var isRecordingAnimated = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(vm.recordings) { recording in
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 8), spacing: 2)], spacing: 2) {
                                ForEach(recording.audioChunks, id: \.index) { chunk in
                                    let color = isCurrent(recording: recording, chunk: chunk)
                                        ? Color.white
                                        : chunk.listened ? Color.blue : Color.purple
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(color)
                                        .animation(vm.isListening ? .easeInOut(duration: 2.4) : nil, value: color)
                                        .frame(height: 48)
                                        .transition(.scale.combined(with: .opacity))
                                        .id("\(recording.id)-\(chunk.index)")
                                }
                            }
                            .animation(.easeInOut(duration: 0.3), value: recording.audioChunks.count)
                        }
                        Color.clear.frame(height: 40).id("bottom")
                    }
                    .padding()
                }
                .scrollDisabled(vm.isRecording || vm.isListening)
                .onChange(of: vm.recordings.last?.audioChunks.count ?? 0) {
                    if vm.isRecording {
                        withAnimation { proxy.scrollTo("bottom") }
                    }
                }
                .onChange(of: vm.playbackPosition) {
                    if let pos = vm.playbackPosition {
                        withAnimation {
                            proxy.scrollTo("\(pos.recordingID)-\(pos.chunkIndex)", anchor: .center)
                        }
                    }
                }
            }

            // Control area: invisible scrubber behind, buttons + chunk number on top
            ZStack {
                if !vm.isListening && !vm.isRecording && vm.totalChunkCount > 0 {
                    InvisibleScrubber(
                        totalChunks: vm.totalChunkCount,
                        currentIndex: vm.cursorGlobalIndex,
                        onIndexChanged: { vm.seekTo($0) }
                    )
                }

                HStack {
                    ListenButton(
                        isListening: vm.isListening,
                        hasUnplayedChunks: vm.hasUnplayedChunks || vm.playbackPosition != nil,
                        onTap: { vm.toggleListening() }
                    )
                    .animation(.easeInOut(duration: 0.3), value: vm.hasUnplayedChunks)

                    Spacer()

                    if vm.totalChunkCount > 0 {
                        Text("\(vm.cursorGlobalIndex)")
                            .font(.system(size: 22, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                    }

                    Spacer()

                    RecordButton(isRecording: isRecordingAnimated, onTap: { vm.toggleRecording() })
                }
                .padding(.horizontal, 40)
            }
            .frame(height: 120)
            .padding(.bottom, 20)
        }
        .onChange(of: vm.isRecording) { _, newValue in
            withAnimation(.spring(duration: 1.0 / φ, bounce: 1.0 - 1.0 / φ)) {
                isRecordingAnimated = newValue
            }
        }
    }
}

// MARK: - Invisible Scrubber

struct InvisibleScrubber: UIViewRepresentable {
    var totalChunks: Int
    var currentIndex: Int
    var onIndexChanged: (Int) -> Void

    static let itemWidth: CGFloat = 20

    func makeCoordinator() -> Coordinator {
        Coordinator(onIndexChanged: onIndexChanged)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let sv = UIScrollView()
        sv.showsHorizontalScrollIndicator = false
        sv.showsVerticalScrollIndicator = false
        sv.decelerationRate = .normal
        sv.delegate = context.coordinator
        sv.backgroundColor = .clear

        let content = UIView()
        content.backgroundColor = .clear
        sv.addSubview(content)
        context.coordinator.contentView = content
        context.coordinator.scrollView = sv

        let haptic = UISelectionFeedbackGenerator()
        haptic.prepare()
        context.coordinator.haptic = haptic

        return sv
    }

    func updateUIView(_ sv: UIScrollView, context: Context) {
        let coord = context.coordinator
        coord.onIndexChanged = onIndexChanged
        coord.totalChunks = totalChunks

        let contentWidth = CGFloat(totalChunks) * Self.itemWidth
        let inset = sv.bounds.width / 2

        coord.contentView?.frame = CGRect(x: 0, y: 0, width: contentWidth, height: sv.bounds.height)
        sv.contentSize = CGSize(width: contentWidth, height: sv.bounds.height)
        sv.contentInset = UIEdgeInsets(top: 0, left: inset, bottom: 0, right: inset)

        if !coord.isUserScrolling {
            let targetX = CGFloat(currentIndex) * Self.itemWidth
            if abs(sv.contentOffset.x - targetX) > 0.5 {
                sv.setContentOffset(CGPoint(x: targetX, y: 0), animated: false)
            }
        }
    }

    class Coordinator: NSObject, UIScrollViewDelegate {
        var onIndexChanged: (Int) -> Void
        var totalChunks: Int = 0
        var isUserScrolling = false
        var lastIndex: Int?
        var scrollView: UIScrollView?
        var contentView: UIView?
        var haptic: UISelectionFeedbackGenerator?

        init(onIndexChanged: @escaping (Int) -> Void) {
            self.onIndexChanged = onIndexChanged
        }

        private func currentIndex(in sv: UIScrollView) -> Int {
            let x = sv.contentOffset.x + InvisibleScrubber.itemWidth / 2
            let index = Int(round(x / InvisibleScrubber.itemWidth))
            return max(0, min(index, totalChunks - 1))
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            isUserScrolling = true
            haptic?.prepare()
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard isUserScrolling else { return }
            let index = currentIndex(in: scrollView)
            if lastIndex != index {
                lastIndex = index
                haptic?.selectionChanged()
                onIndexChanged(index)
            }
        }

        func scrollViewWillEndDragging(_ scrollView: UIScrollView,
                                        withVelocity velocity: CGPoint,
                                        targetContentOffset: UnsafeMutablePointer<CGPoint>) {
            let snapped = round(targetContentOffset.pointee.x / InvisibleScrubber.itemWidth) * InvisibleScrubber.itemWidth
            targetContentOffset.pointee.x = snapped
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            finish(scrollView)
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate { finish(scrollView) }
        }

        private func finish(_ scrollView: UIScrollView) {
            isUserScrolling = false
            let index = currentIndex(in: scrollView)
            onIndexChanged(index)
        }
    }
}

// MARK: - Buttons

struct RecordButton: View {
    let isRecording: Bool
    let onTap: () -> Void

    private static let circleSize: CGFloat = 100
    private static let squareSize: CGFloat = circleSize / φ
    private static let cornerRadius: CGFloat = squareSize / pow(φ, 4)

    var body: some View {
        Button(action: { onTap() }) {
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
    let hasUnplayedChunks: Bool
    let onTap: () -> Void

    private static let size: CGFloat = 100

    var body: some View {
        Button(action: { onTap() }) {
            Image(systemName: isListening ? "pause.fill" : "play.fill")
                .font(.system(size: Self.size))
                .foregroundColor(hasUnplayedChunks ? .purple : .blue)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: Self.size, height: Self.size)
        }
    }
}

// MARK: - Helpers

extension ContentView {
    private func isCurrent(recording: Recording, chunk: AudioChunk) -> Bool {
        guard let pos = vm.playbackPosition else { return false }
        return pos.recordingID == recording.id && pos.chunkIndex == chunk.index
    }
}

// MARK: - Constants

private let φ: CGFloat = (1 + sqrt(5)) / 2
