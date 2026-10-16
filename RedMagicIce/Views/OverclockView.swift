import SwiftUI

struct OverclockView: View {
    @EnvironmentObject var ble: CoolerBLEManager
    @Environment(\.dismiss) private var dismiss
    @StateObject private var lab = OverclockLab()
    @State private var accepted = false

    var body: some View {
        ZStack {
            AppBackground(accent: .red)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    warning
                    if accepted { controls; results }
                }
                .padding(16)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { lab.attach(ble) }
        .onDisappear { if lab.value > OverclockLab.stockMax || lab.sweeping { lab.restore() } }  // 离开时回到安全值
    }

    private var warning: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("超频探测(实验)", systemImage: "exclamationmark.triangle.fill")
                .font(.headline).foregroundStyle(.yellow)
            Text("原版 App 风扇档位最高只写到 80(第 10 档),从未写过更高的值。固件可能忽略、限幅、拒绝,也可能让风扇过载、噪音增大、缩短寿命或触发保护关机。结果完全未经验证,风险自负。")
                .font(.footnote).foregroundStyle(.white.opacity(0.85))
            Toggle("我了解风险,继续", isOn: $accepted).tint(.red)
        }
        .foregroundStyle(.white).glassCard(tint: .red)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("风扇原始值").font(.headline)
                Spacer()
                Text("\(lab.value)").font(.system(size: 34, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(lab.value > OverclockLab.stockMax ? .red : .white)
            }
            Slider(value: Binding(get: { Double(lab.value) }, set: { lab.value = Int($0) }),
                   in: 40...255, step: 1)
                .disabled(lab.sweeping)
            GlassGroup {
                FlowRow {
                    GlassChip(title: "−5", symbol: nil) { lab.value = max(lab.value - 5, 40) }
                    GlassChip(title: "+5", symbol: nil) { lab.value = min(lab.value + 5, 255) }
                    GlassChip(title: "写入", symbol: "arrow.up.circle.fill", selected: true, tint: .red) { lab.apply(lab.value) }
                    GlassChip(title: "恢复第 10 档", symbol: "arrow.uturn.backward") { lab.restore() }
                }
            }
            .disabled(lab.sweeping)
            Toggle("同时开启破坏神(1017)", isOn: $lab.withBoost).disabled(lab.sweeping)
            GlassGroup {
                HStack {
                    if lab.sweeping {
                        GlassChip(title: "停止探测", symbol: "stop.fill", selected: true, tint: .red) { lab.stopSweep() }
                    } else {
                        GlassChip(title: "自动探测", symbol: "wand.and.stars", selected: true, tint: .orange) { lab.startSweep() }
                    }
                }
            }
            HStack {
                Text("当前:\(ble.rpm.map(String.init) ?? "--") RPM · \(ble.powerW.map(String.init) ?? "--") W · \(ble.temperatureC.map { String(format: "%.0f°C", $0) } ?? "--")")
                Spacer()
            }
            .font(.footnote).foregroundStyle(.white.opacity(0.75))
            if !lab.status.isEmpty { Text(lab.status).font(.footnote).foregroundStyle(.yellow.opacity(0.9)) }
            Text("自动探测:从 80 起每 4 档写入一次,每次等 5 秒读转速;出现写入报错、断线,或转速连续两档不再上升就停止,并自动恢复第 10 档。离开本页也会自动恢复。")
                .font(.caption).foregroundStyle(.white.opacity(0.55))
        }
        .foregroundStyle(.white).glassCard()
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("探测记录").font(.headline)
            if lab.samples.isEmpty {
                Text("还没有记录").font(.footnote).foregroundStyle(.white.opacity(0.6))
            } else {
                HStack {
                    Text("写入值").frame(width: 56, alignment: .leading)
                    Text("转速").frame(width: 78, alignment: .leading)
                    Text("功率").frame(width: 48, alignment: .leading)
                    Text("读回").frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.caption).foregroundStyle(.white.opacity(0.6))
                ForEach(lab.samples) { s in
                    HStack {
                        Text("\(s.value)").frame(width: 56, alignment: .leading)
                        Text(s.rpm.map { "\($0)" } ?? "--").frame(width: 78, alignment: .leading)
                        Text(s.powerW.map { "\($0)W" } ?? "--").frame(width: 48, alignment: .leading)
                        Text(s.note).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.system(.footnote, design: .monospaced))
                }
            }
        }
        .foregroundStyle(.white).glassCard()
    }
}
