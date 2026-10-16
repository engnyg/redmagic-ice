import SwiftUI

struct ControlView: View {
    @EnvironmentObject var ble: CoolerBLEManager
    @State private var levelIndex = 0

    private var smartOn: Bool { ble.mode == .smart }
    private var boostOn: Bool { ble.mode == .boost }
    private var manualOn: Bool { if case .manual = ble.mode { return true }; return false }
    private let levelCount = CoolerProtocol.fanLevelValues.count

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if !ble.connected {
                    Label("預覽模式:未連線散熱器,操作不會傳送", systemImage: "eye")
                        .font(.footnote.weight(.semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(10)
                        .glass(Capsule(), tint: .orange)
                }
                header
                stats
                modes
                fanLevels
            }
            .padding(.horizontal, 16).padding(.top, 8)
        }
        .onChange(of: ble.mode) { m in if case .manual(let l) = m { levelIndex = l } }
    }

    private var header: some View {
        VStack(spacing: 14) {
            Text(ble.deviceName).font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.7))
            Button { ble.setPower(!ble.running) } label: {
                Image(systemName: "power").font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.white).frame(width: 128, height: 128)
            }
            .buttonStyle(.plain)
            .glass(Circle(), tint: ble.running ? ble.accent : nil, interactive: true)
            Text(ble.running ? "執行中" : "已關閉").font(.headline).foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
    }

    private var stats: some View {
        GlassGroup {
            HStack(spacing: 12) {
                tile("溫度", ble.temperatureC.map { String(format: "%.0f", $0) }, "°C", "thermometer.medium")
                tile("轉速", ble.rpm.map(String.init), "RPM", "fanblades")
                tile("功率", ble.powerW.map(String.init), "W", "bolt.fill")
            }
        }
    }

    private func tile(_ title: String, _ value: String?, _ unit: String, _ symbol: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).font(.footnote).foregroundStyle(.white.opacity(0.65))
            Text(value ?? "--").font(.system(size: 28, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                .contentTransition(.numericText()).animation(.default, value: value)
            Text(unit).font(.caption2).foregroundStyle(.white.opacity(0.6))
            Text(title).font(.caption).foregroundStyle(.white.opacity(0.75))
        }
        .frame(maxWidth: .infinity).padding(.vertical, 16)
        .glass(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var modes: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("模式")
            GlassGroup {
                HStack(spacing: 10) {
                    GlassChip(title: "手動", symbol: "slider.horizontal.3", selected: manualOn, tint: .cyan) {
                        ble.setManual(level: levelIndex)
                    }
                    GlassChip(title: "智慧溫控", symbol: "brain", selected: smartOn, tint: .green) { ble.setSmart(!smartOn) }
                    GlassChip(title: "破壞神", symbol: "flame.fill", selected: boostOn, tint: .red) { ble.setBoost(!boostOn) }
                }
            }
        }
    }

    private var fanLevels: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("手動檔位").font(.headline)
                Spacer()
                Text("\(levelIndex + 1) / \(levelCount)").monospacedDigit().foregroundStyle(.white.opacity(0.7))
            }
            GeometryReader { geo in
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(0..<levelCount, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(i <= levelIndex ? ble.accent : Color.white.opacity(0.18))
                            .frame(height: 20 + CGFloat(i) * 6)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .bottom)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let i = Int(v.location.x / geo.size.width * CGFloat(levelCount))
                        levelIndex = min(max(i, 0), levelCount - 1)
                    }
                    .onEnded { _ in ble.setManual(level: levelIndex) })
            }
            .frame(height: 86)
        }
        .foregroundStyle(.white).glassCard()
    }
}
