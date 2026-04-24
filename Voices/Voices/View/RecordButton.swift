import SwiftUI

private let φ: CGFloat = (1 + sqrt(5)) / 2

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
