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
    var onScrubMove: ((Int) -> Void)?
    var onScrubEnd: ((Int) -> Void)?

    @State private var dragOffset: CGFloat = 0
    @State private var isScrubbing = false
    @State private var coastTask: Task<Void, Never>?

    private static let overscan = 20
    private static let decel: CGFloat = 0.97      // per 16ms tick
    private static let minSpeed: CGFloat = 30      // px/sec settle threshold

    var body: some View {
        GeometryReader { geo in
            let center = geo.size.width / 2
            let target = activeIndex ?? max(chunks.count - 1, 0)
            let base = center - CGFloat(target) * step
            let effectiveOffset = isScrubbing ? base + dragOffset : base

            let lo = max(0, Int(floor(-effectiveOffset / step)) - Self.overscan)
            let hi = min(chunks.count, Int(ceil((geo.size.width - effectiveOffset) / step)) + Self.overscan)

            TimelineView(.animation) { _ in
                HStack(spacing: gap) {
                    if hi > lo {
                        ForEach(chunks[lo..<hi]) { chunk in
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(chunk.status.color)
                                .frame(width: barW, height: barH)
                        }
                    }
                }
                .offset(x: effectiveOffset + CGFloat(lo) * step)
            }
            .gesture(chunks.isEmpty ? nil :
                DragGesture()
                    .onChanged { value in
                        coastTask?.cancel()
                        if !isScrubbing {
                            isScrubbing = true
                            onScrubStart?()
                        }
                        dragOffset = clampDrag(value.translation.width, base: base, center: center)
                        onScrubMove?(scrubIndex(base: base, center: center, offset: dragOffset))
                    }
                    .onEnded { value in
                        let vel = (value.predictedEndTranslation.width - value.translation.width) / 0.25
                        if abs(vel) > Self.minSpeed * 3 {
                            coast(velocity: vel, base: base, center: center)
                        } else {
                            settle(base: base, center: center, offset: value.translation.width)
                        }
                    }
            )
        }
        .frame(height: barH)
        .padding(.vertical, 10)
        .onChange(of: activeIndex) {
            if activeIndex != nil && isScrubbing {
                coastTask?.cancel()
                dragOffset = 0
                isScrubbing = false
            }
        }
    }

    private func coast(velocity startVel: CGFloat, base: CGFloat, center: CGFloat) {
        coastTask?.cancel()
        coastTask = Task { @MainActor in
            var vel = startVel
            while !Task.isCancelled && abs(vel) > Self.minSpeed {
                try? await Task.sleep(for: .milliseconds(16))
                dragOffset = clampDrag(dragOffset + vel * 0.016, base: base, center: center)
                vel *= Self.decel
                onScrubMove?(scrubIndex(base: base, center: center, offset: dragOffset))
            }
            if !Task.isCancelled { settle(base: base, center: center, offset: dragOffset) }
        }
    }

    private func settle(base: CGFloat, center: CGFloat, offset: CGFloat) {
        let clamped = scrubIndex(base: base, center: center, offset: offset)
        dragOffset = 0
        isScrubbing = false
        onScrubEnd?(clamped)
    }

    private func clampDrag(_ raw: CGFloat, base: CGFloat, center: CGFloat) -> CGFloat {
        let maxDrag = center - base                                                    // chunk 0 at center
        let minDrag = center - CGFloat(max(chunks.count - 1, 0)) * step - base        // last chunk at center
        return min(maxDrag, max(minDrag, raw))
    }

    private func scrubIndex(base: CGFloat, center: CGFloat, offset: CGFloat) -> Int {
        let idx = Int(round((center - base - offset) / step))
        return max(0, min(chunks.count - 1, idx))
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
