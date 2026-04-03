import SwiftUI

// MARK: - Horizontal chunk strip

struct ChunkStrip: View {
    let chunks: [ChunkStore.ChunkEntry]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(chunks) { chunk in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(chunk.status.color)
                            .frame(width: 6, height: 30)
                            .id(chunk.id)
                    }
                }
                .padding(.horizontal, 40)
            }
            .onChange(of: chunks.count) {
                if let last = chunks.last {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(last.id, anchor: .trailing)
                    }
                }
            }
        }
    }
}
