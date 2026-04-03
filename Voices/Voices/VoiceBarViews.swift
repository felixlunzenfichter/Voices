import SwiftUI

// MARK: - Horizontal chunk strip

private let barW: CGFloat = 6
private let barH: CGFloat = 30
private let gap: CGFloat = 2
private let step: CGFloat = barW + gap  // 8pt per chunk

struct ChunkStrip: View {
    let chunks: [ChunkStore.ChunkEntry]
    var activeIndex: Int?

    var body: some View {
        GeometryReader { geo in
            let center = geo.size.width / 2
            let offset: CGFloat = {
                guard let i = activeIndex else {
                    // No active bar — pin last chunk to center (or 0 if empty)
                    let last = max(chunks.count - 1, 0)
                    return center - CGFloat(last) * step
                }
                return center - CGFloat(i) * step
            }()

            HStack(spacing: gap) {
                ForEach(chunks) { chunk in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(chunk.status.color)
                        .frame(width: barW, height: barH)
                }
            }
            .offset(x: offset)
            .animation(.easeOut(duration: 0.12), value: activeIndex)
            .animation(.easeOut(duration: 0.12), value: chunks.count)
        }
        .frame(height: barH)
        .allowsHitTesting(false)
    }
}
