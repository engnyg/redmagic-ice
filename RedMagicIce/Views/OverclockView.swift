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
        .onDisappear { if lab.value > OverclockLab.stockMax || lab.sweeping { lab.restore() } }  // 離開時回到安全值
    }

    private var warning: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("超頻探測(實驗)", systemImage: "exclamationmark.triangle.fill")
                .font(.headline).foregroundStyle(.yellow)
            Text("原版 App 風扇檔位最高只寫到 80(第 10 檔),從未寫過更高的值。韌體可能忽略、限幅、拒絕,也可能讓風扇過載、噪音增大、縮短壽命或觸發保護關機。結果完全未經驗證,風險自負。")
                .font(.footnote).foregroundStyle(.white.opacity(0.85))
            Toggle("我瞭解風險,繼續", isOn: $accepted).tint(.red)
        }
        .foregroundStyle(.white).glassCard(tint: .red)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("風扇原始值").font(.headline)
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
                    GlassChip(title: "寫入", symbol: "arrow.up.circle.fill", selected: true, tint: .red) { lab.apply(lab.value) }
                    GlassChip(title: "恢復第 10 檔", symbol: "arrow.uturn.backward") { lab.restore() }
                }
            }
            .disabled(lab.sweeping)
            Toggle("同時開啟破壞神(1017)", isOn: $lab.withBoost).disabled(lab.sweeping)
            GlassGroup {
                HStack {
                    if lab.sweeping {
                        GlassChip(title: "停止探測", symbol: "stop.fill", selected: true, tint: .red) { lab.stopSweep() }
                    } else {
                        GlassChip(title: "自動探測", symbol: "wand.and.stars", selected: true, tint: .orange) { lab.startSweep() }
                    }
                }
            }
            HStack {
                Text("當前:\(ble.rpm.map(String.init) ?? "--") RPM · \(ble.powerW.map(String.init) ?? "--") W · \(ble.temperatureC.map { String(format: "%.0f°C", $0) } ?? "--")")
                Spacer()
            }
            .font(.footnote).foregroundStyle(.white.opacity(0.75))
            if !lab.status.isEmpty { Text(lab.status).font(.footnote).foregroundStyle(.yellow.opacity(0.9)) }
            Text("自動探測:從 80 起每 4 檔寫入一次,每次等 5 秒讀轉速;出現寫入報錯、斷線,或轉速連續兩檔不再上升就停止,並自動恢復第 10 檔。離開本頁也會自動恢復。")
                .font(.caption).foregroundStyle(.white.opacity(0.55))
        }
        .foregroundStyle(.white).glassCard()
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("探測記錄").font(.headline)
            if lab.samples.isEmpty {
                Text("還沒有記錄").font(.footnote).foregroundStyle(.white.opacity(0.6))
            } else {
                HStack {
                    Text("寫入值").frame(width: 56, alignment: .leading)
                    Text("轉速").frame(width: 78, alignment: .leading)
                    Text("功率").frame(width: 48, alignment: .leading)
                    Text("讀回").frame(maxWidth: .infinity, alignment: .leading)
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
