import SwiftUI

/// 可拖曳的「溫度 → 檔位」曲線編輯器:拖曳圓點同時調整該點的溫度(左右)與檔位(上下)。
struct CurveEditor: View {
    @Binding var curve: TempCurve
    let range: ClosedRange<Double>
    var currentTemp: Double?
    @State private var active: Int?

    private let padL: CGFloat = 30, padR: CGFloat = 14, padT: CGFloat = 14, padB: CGFloat = 24

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                let w = geo.size.width - padL - padR
                let h = geo.size.height - padT - padB
                ZStack(alignment: .topLeading) {
                    grid(w: w, h: h)
                    if let t = currentTemp, range.contains(t) {
                        Path { p in
                            p.move(to: CGPoint(x: xPos(t, w), y: padT))
                            p.addLine(to: CGPoint(x: xPos(t, w), y: padT + h))
                        }
                        .stroke(Color.yellow.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    }
                    Path { p in
                        let pts = curve.points.sorted { $0.temp < $1.temp }
                        for (i, pt) in pts.enumerated() {
                            let c = CGPoint(x: xPos(pt.temp, w), y: yPos(pt.level, h))
                            if i == 0 { p.move(to: c) } else { p.addLine(to: c) }
                        }
                    }
                    .stroke(Color.cyan, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    ForEach(curve.points.indices, id: \.self) { i in
                        Circle()
                            .fill(active == i ? Color.white : Color.cyan)
                            .overlay(Circle().stroke(Color.white.opacity(0.85), lineWidth: 2))
                            .frame(width: 24, height: 24)
                            .position(x: xPos(curve.points[i].temp, w), y: yPos(curve.points[i].level, h))
                            .gesture(
                                DragGesture(minimumDistance: 0, coordinateSpace: .named("plot"))
                                    .onChanged { v in active = i; move(i, to: v.location, w: w, h: h) }
                                    .onEnded { _ in active = nil }
                            )
                    }
                }
                .coordinateSpace(name: "plot")
            }
            .frame(height: 240)
            Text(readout).font(.footnote.monospacedDigit()).foregroundStyle(.white.opacity(0.75))
        }
    }

    private var readout: String {
        if let i = active, curve.points.indices.contains(i) {
            let p = curve.points[i]
            return String(format: "第 %d 點:%.1f°C → %.1f 檔", i + 1, p.temp, p.level)
        }
        return "拖曳圓點調整曲線(左右=溫度,上下=檔位)。黃色虛線為目前溫度。"
    }

    private func grid(w: CGFloat, h: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach([1, 4, 7, 10], id: \.self) { lv in
                Path { p in
                    p.move(to: CGPoint(x: padL, y: yPos(Double(lv), h)))
                    p.addLine(to: CGPoint(x: padL + w, y: yPos(Double(lv), h)))
                }
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                Text("\(lv)").font(.caption2).foregroundStyle(.white.opacity(0.6))
                    .position(x: 12, y: yPos(Double(lv), h))
            }
            Text(String(format: "%.0f°", range.lowerBound)).font(.caption2).foregroundStyle(.white.opacity(0.6))
                .position(x: padL, y: padT + h + 14)
            Text(String(format: "%.0f°", range.upperBound)).font(.caption2).foregroundStyle(.white.opacity(0.6))
                .position(x: padL + w, y: padT + h + 14)
        }
    }

    private func xPos(_ t: Double, _ w: CGFloat) -> CGFloat {
        padL + CGFloat((t - range.lowerBound) / (range.upperBound - range.lowerBound)) * w
    }

    private func yPos(_ level: Double, _ h: CGFloat) -> CGFloat {
        padT + h - CGFloat((level - 1) / 9) * h
    }

    private func move(_ i: Int, to p: CGPoint, w: CGFloat, h: CGFloat) {
        var pts = curve.points
        guard pts.indices.contains(i) else { return }
        let tRaw = range.lowerBound + Double((p.x - padL) / w) * (range.upperBound - range.lowerBound)
        let lRaw = 1 + Double((padT + h - p.y) / h) * 9
        let lo = i > 0 ? pts[i - 1].temp + 0.5 : range.lowerBound
        let hi = max(lo, i < pts.count - 1 ? pts[i + 1].temp - 0.5 : range.upperBound)
        pts[i].temp = (min(max(tRaw, lo), hi) * 2).rounded() / 2
        pts[i].level = (min(max(lRaw, 1), 10) * 2).rounded() / 2
        curve.points = pts
    }
}
