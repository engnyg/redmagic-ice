import SwiftUI

/// 全螢幕調整背景照片的位置與縮放:單指拖曳、雙指縮放,畫面就是實際背景的樣子。
struct PhotoPositionEditor: View {
    let image: UIImage
    let blur: Double
    let dim: Double
    var onDone: (_ scale: Double, _ x: Double, _ y: Double) -> Void
    var onCancel: () -> Void

    @State private var scale: Double
    @State private var x: Double
    @State private var y: Double
    @GestureState private var drag: CGSize = .zero
    @GestureState private var pinch: CGFloat = 1

    init(image: UIImage, blur: Double, dim: Double, scale: Double, x: Double, y: Double,
         onDone: @escaping (Double, Double, Double) -> Void, onCancel: @escaping () -> Void) {
        self.image = image; self.blur = blur; self.dim = dim
        self.onDone = onDone; self.onCancel = onCancel
        _scale = State(initialValue: scale); _x = State(initialValue: x); _y = State(initialValue: y)
    }

    private func effectiveScale() -> Double { min(max(scale * Double(pinch), 1), 5) }

    var body: some View {
        GeometryReader { geo in
            let f = PhotoLayout.frame(image: image.size, container: geo.size,
                                      scale: effectiveScale(), x: x, y: y, drag: drag)
            ZStack {
                Color.black
                Image(uiImage: image).resizable()
                    .frame(width: f.size.width, height: f.size.height)
                    .blur(radius: blur)
                    .offset(f.offset)
                Color.black.opacity(dim)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .updating($drag) { v, state, _ in state = v.translation }
                    .onEnded { v in
                        let r = PhotoLayout.frame(image: image.size, container: geo.size,
                                                  scale: scale, x: x, y: y, drag: v.translation)
                        let n = PhotoLayout.normalized(r.offset, maxOffset: r.maxOffset)
                        x = n.x; y = n.y
                    }
                    .simultaneously(with:
                        MagnificationGesture()
                            .updating($pinch) { v, state, _ in state = v }
                            .onEnded { v in
                                let ns = min(max(scale * Double(v), 1), 5)
                                // 縮放後,以同樣的「點」偏移換算回比例,避免畫面跳動
                                let before = PhotoLayout.frame(image: image.size, container: geo.size, scale: scale, x: x, y: y)
                                let after = PhotoLayout.frame(image: image.size, container: geo.size, scale: ns, x: x, y: y)
                                let clamped = PhotoLayout.frame(image: image.size, container: geo.size, scale: ns, x: 0, y: 0,
                                                                drag: before.offset)
                                let n = PhotoLayout.normalized(clamped.offset, maxOffset: after.maxOffset)
                                scale = ns; x = n.x; y = n.y
                            }
                    )
            )
            .overlay(alignment: .top) {
                Text("拖曳移動,雙指縮放").font(.footnote.weight(.semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, geo.safeAreaInsets.top + 12)
            }
            .overlay(alignment: .bottom) {
                HStack(spacing: 12) {
                    GlassChip(title: "取消", symbol: "xmark") { onCancel() }
                    GlassChip(title: "重設", symbol: "arrow.counterclockwise") { scale = 1; x = 0; y = 0 }
                    GlassChip(title: "完成", symbol: "checkmark", selected: true, tint: .green) { onDone(scale, x, y) }
                }
                .padding(.bottom, geo.safeAreaInsets.bottom + 16)
            }
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
    }
}
