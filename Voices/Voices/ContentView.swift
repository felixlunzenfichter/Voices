import SwiftUI

struct ContentView: View {
    @State private var vm: VoicesViewModel = {
        let db = InMemoryDatabase()
        db.addRecording(Recording(audioChunks: (0..<5).map { AudioChunk(index: $0) }))
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
                                    let color = vm.isCurrent(recording: recording, chunk: chunk)
                                        ? Color.white
                                        : chunk.listened ? Color.blue : Color.purple
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(color)
                                        .animation(vm.shouldAnimateChunks ? .easeInOut(duration: 0.3) : nil, value: color)
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

            ZStack {
                if vm.canSeek {
                    SwiftUIScrubber(vm: vm)
                }

                HStack {
                    ListenButton(
                        isListening: vm.isListening,
                        hasUnplayedChunks: vm.hasUnplayedChunks,
                        canPlay: vm.canPlay,
                        onTap: { vm.toggleListening() }
                    )
                    .animation(.easeInOut(duration: 0.3), value: vm.hasUnplayedChunks)

                    Spacer()

                    if vm.totalChunkCount > 0 {
                        VStack {
                            Text("\(vm.displayChunkNumber)")
                                .font(.system(size: 28, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                                .padding(.top, 10)
                            Spacer()
                        }
                    }

                    Spacer()

                    RecordButton(isRecording: isRecordingAnimated, onTap: { vm.toggleRecording() })
                }
                .padding(.horizontal, 40)
            }
            .frame(height: 120)
            .padding(.bottom, 20)
        }
        .sensoryFeedback(.selection, trigger: vm.playbackPosition)
        .onChange(of: vm.isRecording) { _, newValue in
            withAnimation(.spring(duration: 1.0 / φ, bounce: 1.0 - 1.0 / φ)) {
                isRecordingAnimated = newValue
            }
        }
    }
}

// MARK: - SwiftUI Scrubber

struct SwiftUIScrubber: View {
    @Bindable var vm: VoicesViewModel
    @State private var scrolledID: Int?

    private static let itemWidth: CGFloat = 20

    var body: some View {
        GeometryReader { geo in
            let inset = geo.size.width / 2 - Self.itemWidth / 2
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(0...vm.totalChunkCount, id: \.self) { i in
                        Color.clear
                            .frame(width: Self.itemWidth, height: 1)
                            .id(i)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, inset, for: .scrollContent)
            .scrollPosition(id: $scrolledID, anchor: .center)
        }
        .onAppear {
            scrolledID = vm.scrubberIndex
        }
        .onChange(of: scrolledID) { _, new in
            guard let id = new else { return }
            vm.shouldAnimateChunks = false
            vm.seekTo(id)
        }
        .onDisappear {
            vm.shouldAnimateChunks = true
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
    let canPlay: Bool
    let onTap: () -> Void

    private static let size: CGFloat = 100

    var body: some View {
        Button(action: { onTap() }) {
            Image(systemName: isListening ? "pause.fill" : "play.fill")
                .font(.system(size: Self.size))
                .foregroundColor(hasUnplayedChunks ? .purple : .blue)
                .opacity(canPlay || isListening ? 1.0 : 0.3)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: Self.size, height: Self.size)
        }
        .disabled(!canPlay && !isListening)
    }
}

// MARK: - Constants

private let φ: CGFloat = (1 + sqrt(5)) / 2
