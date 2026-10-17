import SwiftUI

/// 圓形色盤:角度是色相、離圓心越遠越飽和,下方滑桿調亮度。點一下色票展開 / 收合。
struct WheelColorPicker: View {
    let title: String
    @Binding var color: RGB
    @State private var expanded = false
    @State private var h = 0.0, s = 0.0, v = 1.0

    init(_ title: String, color: Binding<RGB>) {
        self.title = title
        _color = color
    }

    private let diameter: CGFloat = 220

    var body: some View {
        VStack(spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack {
                    if !title.isEmpty { Text(title) }
                    Spacer(minLength: 8)
                    Circle().fill(color.color)
                        .frame(width: 30, height: 30)
                        .overlay(Circle().stroke(Color.white.opacity(0.7), lineWidth: 1.5))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                wheel
                HStack(spacing: 10) {
                    Image(systemName: "sun.min").foregroundStyle(.white.opacity(0.7))
                    Slider(value: Binding(get: { v }, set: { v = $0; push() }), in: 0...1)
                    Image(systemName: "sun.max.fill").foregroundStyle(.white.opacity(0.7))
                }
                .frame(maxWidth: diameter + 40)
            }
        }
        .onAppear { sync(from: color) }
        .onChange(of: color) { new in
            if new != RGB.hsv(h, s, v) { sync(from: new) }   // 外部改了顏色(預設色、彩虹環…)才重新同步
        }
    }

    private var wheel: some View {
        let r = diameter / 2
        let hueColors = (0...12).map { Color(hue: Double($0) / 12, saturation: 1, brightness: 1) }
        return ZStack {
            Circle().fill(AngularGradient(gradient: Gradient(colors: hueColors), center: .center))
            Circle().fill(RadialGradient(colors: [.white, Color.white.opacity(0)], center: .center, startRadius: 0, endRadius: r))
            Circle().fill(Color.black.opacity(1 - v))
            Circle().stroke(Color.white.opacity(0.35), lineWidth: 1)
            let a = h / 360 * 2 * Double.pi
            Circle().fill(color.color)
                .frame(width: 26, height: 26)
                .overlay(Circle().stroke(Color.white, lineWidth: 3))
                .shadow(color: .black.opacity(0.4), radius: 3)
                .offset(x: CGFloat(cos(a)) * r * CGFloat(s), y: CGFloat(sin(a)) * r * CGFloat(s))
        }
        .frame(width: diameter, height: diameter)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0).onChanged { g in
                let dx = g.location.x - r, dy = g.location.y - r
                var angle = atan2(dy, dx)
                if angle < 0 { angle += 2 * .pi }
                h = Double(angle) / (2 * Double.pi) * 360
                s = min(Double(hypot(dx, dy) / r), 1)
                push()
            }
        )
        .frame(maxWidth: .infinity)
    }

    private func push() { color = RGB.hsv(h, s, v) }

    private func sync(from c: RGB) {
        let x = c.hsv
        v = x.v
        if x.v > 0.001 {
            s = x.s
            if x.s > 0.001 { h = x.h }      // 黑 / 灰沒有色相資訊:保留原本的,避免拖亮度時色相跳掉
        }
    }
}
