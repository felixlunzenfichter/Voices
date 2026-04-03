import SwiftUI

// MARK: - Horizontal chunk strip

struct ChunkStrip: View {
    let chunks: [ChunkStore.ChunkEntry]
    var activeId: UUID?

    var body: some View {
        GeometryReader { geo in
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
                    .padding(.horizontal, geo.size.width / 2)
                }
                .onChange(of: activeId) {
                    if let id = activeId {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }
        }
        .frame(height: 30)
    }
}
