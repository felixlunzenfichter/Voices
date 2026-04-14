import SwiftUI

struct ContentView: View {
    @State private var vm: VoicesViewModel = {
        let db = InMemoryDatabase()
        return VoicesViewModel(
            recordingService: DemoRecordingService(),
            playbackService: DemoPlaybackService(database: db),
            database: db
        )
    }()
    @State private var isRecordingAnimated = false

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(vm.recordings) { recording in
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 8), spacing: 2)], spacing: 2) {
                                ForEach(recording.audioChunks, id: \.index) { chunk in
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(isPlayed(recording: recording, chunkIndex: chunk.index) ? Color.blue : Color.purple)
                                        .frame(height: 48)
                                        .transition(.scale.combined(with: .opacity))
                                        .id("\(recording.id)-\(chunk.index)")
                                }
                            }
                            .animation(.easeInOut(duration: 0.3), value: recording.audioChunks.count)
                        }
                        Color.clear.frame(height: 160).id("bottom")
                    }
                    .padding()
                    .animation(.easeInOut(duration: 0.3), value: vm.playbackPosition)
                }
                .scrollDisabled(vm.isRecording || vm.isListening)
                .onChange(of: vm.recordings.last?.audioChunks.count ?? 0) {
                    if vm.isRecording {
                        withAnimation {
                            proxy.scrollTo("bottom")
                        }
                    }
                }
                .onChange(of: vm.playbackPosition) {
                    if let position = vm.playbackPosition, vm.isListening {
                        withAnimation {
                            proxy.scrollTo("\(position.recordingID)-\(position.chunkIndex)", anchor: .center)
                        }
                    }
                }
            }

            HStack {
                ListenButton(isListening: vm.isListening, hasUnplayedChunks: vm.hasUnplayedChunks, onTap: { vm.toggleListening() })
                    .animation(.easeInOut(duration: 0.3), value: vm.hasUnplayedChunks)
                Spacer()
                RecordButton(isRecording: isRecordingAnimated, onTap: { vm.toggleRecording() })
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 60)
        }
        .onChange(of: vm.isRecording) { _, newValue in
            withAnimation(.spring(duration: 1.0 / φ, bounce: 1.0 - 1.0 / φ)) {
                isRecordingAnimated = newValue
            }
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
                .foregroundColor(hasUnplayedChunks ? .purple : .blue)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: Self.size, height: Self.size)
        }
    }
}

// MARK: - Helpers

extension ContentView {
    func isPlayed(recording: Recording, chunkIndex: Int) -> Bool {
        guard let position = vm.playbackPosition else { return false }
        guard let positionRecordingIndex = vm.recordings.firstIndex(where: { $0.id == position.recordingID }),
              let thisRecordingIndex = vm.recordings.firstIndex(where: { $0.id == recording.id })
        else { return false }
        if thisRecordingIndex < positionRecordingIndex { return true }
        if thisRecordingIndex > positionRecordingIndex { return false }
        return chunkIndex <= position.chunkIndex
    }
}

// MARK: - Constants

let φ: CGFloat = (1 + sqrt(5)) / 2
