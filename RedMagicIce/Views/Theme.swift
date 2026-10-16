import SwiftUI
import UIKit

// MARK: - 液态玻璃(iOS 26+ 用 glassEffect,低版本/旧 Xcode 自动降级为毛玻璃)

extension View {
    @ViewBuilder
    func glass<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            let base: Glass = tint.map { Glass.regular.tint($0.opacity(0.45)) } ?? Glass.regular
            self.glassEffect(interactive ? base.interactive() : base, in: shape)
        } else {
            self.materialGlass(shape, tint: tint)
        }
        #else
        self.materialGlass(shape, tint: tint)
        #endif
    }

    func materialGlass<S: Shape>(_ shape: S, tint: Color?) -> some View {
        self
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.fill((tint ?? .clear).opacity(0.22)))
            .overlay(shape.stroke(Color.white.opacity(0.18), lineWidth: 0.8))
    }

    func glassCard(tint: Color? = nil) -> some View {
        self.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .glass(RoundedRectangle(cornerRadius: 28, style: .continuous), tint: tint)
    }
}

/// 让相邻的玻璃元素互相融合(iOS 26),低版本直接透传。
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: () -> Content
    var body: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content() }
        } else {
            content()
        }
        #else
        content()
        #endif
    }
}

struct AuroraBackground: View {
    var accent: Color
    @State private var drift = false
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.03, green: 0.04, blue: 0.10), Color(red: 0.08, green: 0.06, blue: 0.20)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(accent.opacity(0.55)).frame(width: 340, height: 340).blur(radius: 90)
                .offset(x: drift ? 110 : -120, y: drift ? -220 : -120)
            Circle().fill(Color.purple.opacity(0.40)).frame(width: 300, height: 300).blur(radius: 100)
                .offset(x: drift ? -130 : 120, y: drift ? 260 : 160)
            Circle().fill(Color.cyan.opacity(0.30)).frame(width: 260, height: 260).blur(radius: 90)
                .offset(x: drift ? 120 : -80, y: drift ? 80 : 300)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 1.2), value: accent)
        .onAppear { withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) { drift = true } }
    }
}

// MARK: - 通用控件

struct GlassChip: View {
    let title: String
    var symbol: String?
    var selected = false
    var tint: Color = .accentColor
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol) }
                Text(title).lineLimit(1)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .glass(Capsule(), tint: selected ? tint : nil, interactive: true)
    }
}

struct SectionTitle: View {
    let text: String
    init(_ t: String) { text = t }
    var body: some View { Text(text).font(.footnote.weight(.semibold)).foregroundStyle(.white.opacity(0.65)).padding(.leading, 6) }
}

extension RGB {
    var color: Color { Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255) }
    init(_ c: Color) {
        var rr: CGFloat = 0, gg: CGFloat = 0, bb: CGFloat = 0, aa: CGFloat = 0
        UIColor(c).getRed(&rr, green: &gg, blue: &bb, alpha: &aa)
        func u(_ v: CGFloat) -> UInt8 { UInt8(min(max((v * 255).rounded(), 0), 255)) }
        self.init(r: u(rr), g: u(gg), b: u(bb))
    }
}

func rgbBinding(_ b: Binding<RGB>) -> Binding<Color> {
    Binding(get: { b.wrappedValue.color }, set: { b.wrappedValue = RGB($0) })
}
