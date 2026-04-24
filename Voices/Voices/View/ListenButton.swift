import SwiftUI

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
