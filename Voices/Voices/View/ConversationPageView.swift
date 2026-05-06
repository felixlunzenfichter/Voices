import SwiftUI

/// One page of the two-page demo: the existing single-conversation UI,
/// parameterized by which VM it reads. Pure presentation — no harness,
/// no DB construction. The chunk color rule is unchanged from the
/// pre-demo build (`chunk.listened: Bool`); per-viewer color
/// divergence is deliberately out of scope for this slice.
struct ConversationPageView: View {
    @Bindable var vm: VoicesViewModel
    let title: String
    @State private var isRecordingAnimated = false

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .padding(.top, 12)
                .padding(.bottom, 4)

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
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .sensoryFeedback(.selection, trigger: vm.playbackPosition)
        .sensoryFeedback(.selection, trigger: vm.totalChunkCount)
        .onChange(of: vm.isRecording) { _, newValue in
            withAnimation(.spring(duration: 1.0 / φ, bounce: 1.0 - 1.0 / φ)) {
                isRecordingAnimated = newValue
            }
        }
    }
}

private let φ: CGFloat = (1 + sqrt(5)) / 2
