import SwiftUI

// MARK: - Horizontal chunk strip (non-interactive, centered on active bar)

private let barW: CGFloat = 6
private let barH: CGFloat = 30
private let gap: CGFloat = 2
private let step: CGFloat = barW + gap

struct ChunkStrip: View {
    let chunks: [ChunkEntry]
    var activeIndex: Int?
    var onScrubStart: (() -> Void)?
    var onScrubEnd: ((Int) -> Void)?

    @State private var dragOffset: CGFloat = 0
    @State private var isScrubbing = false
    @State private var displayOffset: CGFloat = 0
    @State private var seeded = false

    private static let smoothing: CGFloat = 0.25

    var body: some View {
        GeometryReader { geo in
            let center = geo.size.width / 2
            let target = activeIndex ?? max(chunks.count - 1, 0)
            let base = center - CGFloat(target) * step
            let goal = isScrubbing ? base + dragOffset : base

            TimelineView(.animation) { _ in
                let _ = advance(toward: goal)

                HStack(spacing: gap) {
                    ForEach(chunks) { chunk in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(chunk.status.color)
                            .frame(width: barW, height: barH)
                    }
                }
                .offset(x: displayOffset)
            }
            .gesture(chunks.isEmpty ? nil :
                DragGesture()
                    .onChanged { value in
                        if !isScrubbing {
                            isScrubbing = true
                            onScrubStart?()
                        }
                        dragOffset = value.translation.width
                    }
                    .onEnded { value in
                        let final_ = base + value.translation.width
                        let idx = Int(round((center - final_) / step))
                        let clamped = max(0, min(chunks.count - 1, idx))
                        dragOffset = 0
                        isScrubbing = false
                        onScrubEnd?(clamped)
                    }
            )
        }
        .frame(height: barH)
        .padding(.vertical, 10)
    }

    private func advance(toward goal: CGFloat) {
        if !seeded { displayOffset = goal; seeded = true; return }
        if isScrubbing { displayOffset = goal; return }
        let delta = goal - displayOffset
        if abs(delta) < 0.5 { displayOffset = goal }
        else { displayOffset += delta * Self.smoothing }
    }
}

// MARK: - Message list (scrollable, shows all recordings as flow-layout bubbles)

struct MessageList: View {
    let recordings: [Recording]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(recordings) { recording in
                        MessageBubble(recording: recording)
                            .id(recording.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .onChange(of: recordings.last?.chunks.count) {
                if let id = recordings.last?.id {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(id, anchor: .bottom)
                    }
                }
            }
        }
    }
}

private struct MessageBubble: View {
    let recording: Recording

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(recording.createdAt, style: .time)
                .font(.caption2)
                .foregroundStyle(.secondary)

            FlowLayout(spacing: 2) {
                ForEach(recording.chunks) { chunk in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(chunk.status.color)
                        .frame(width: 6, height: 30)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
            )
        }
    }
}

// MARK: - FlowLayout (wrapping horizontal layout)

struct FlowLayout: Layout {
    var spacing: CGFloat = 2

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
