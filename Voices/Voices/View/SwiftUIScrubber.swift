import SwiftUI

struct SwiftUIScrubber: View {
    @Bindable var vm: VoicesViewModel
    @State private var scrolledID: Int?

    private static let itemWidth: CGFloat = 20

    var body: some View {
        GeometryReader { geo in
            let inset = geo.size.width / 2 - Self.itemWidth / 2
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(0...vm.totalChunkCount, id: \.self) { i in
                        Color.clear
                            .frame(width: Self.itemWidth, height: 1)
                            .id(i)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, inset, for: .scrollContent)
            .scrollPosition(id: $scrolledID, anchor: .center)
        }
        .onAppear {
            scrolledID = vm.scrubberIndex
        }
        .onChange(of: scrolledID) { _, new in
            guard let id = new else { return }
            vm.shouldAnimateChunks = false
            vm.seekTo(id)
        }
        .onDisappear {
            vm.shouldAnimateChunks = true
        }
    }
}
