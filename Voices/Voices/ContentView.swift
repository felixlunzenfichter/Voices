import SwiftUI

struct ContentView: View {
    @State private var vm = VoicesViewModel(
        recordingService: DemoRecordingService(),
        playbackService: DemoPlaybackService()
    )

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 8), spacing: 2)], spacing: 2) {
                    ForEach(vm.recordings.last?.audioChunks ?? [], id: \.index) { chunk in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(chunk.index <= vm.playbackIndex ? Color.blue : Color.purple)
                            .frame(height: 48)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding()
                .animation(.easeInOut(duration: 0.3), value: vm.recordings.last?.audioChunks.count ?? 0)
                .animation(.easeInOut(duration: 0.3), value: vm.playbackIndex)
            }

            HStack {
                ListenButton(isListening: vm.isListening, hasUnplayedChunks: vm.hasUnplayedChunks, onTap: { vm.toggleListening() })
                    .animation(.easeInOut(duration: 0.3), value: vm.hasUnplayedChunks)
                Spacer()
                RecordButton(isRecording: vm.isRecording, onTap: { vm.toggleRecording() })
                    .animation(.spring(duration: 1.0 / φ, bounce: 1.0 - 1.0 / φ), value: vm.isRecording)
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

    var body: some View {
        Button(action: {
            onTap()
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
    let hasUnplayedChunks: Bool
    let onTap: () -> Void

    private static let size: CGFloat = 100

    var body: some View {
        Button(action: {
            onTap()
        }) {
            Image(systemName: isListening ? "pause.fill" : "play.fill")
                .font(.system(size: Self.size))
                .foregroundColor(hasUnplayedChunks ? .blue : .purple)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: Self.size, height: Self.size)
        }
    }
}

// MARK: - Constants

let φ: CGFloat = (1 + sqrt(5)) / 2
