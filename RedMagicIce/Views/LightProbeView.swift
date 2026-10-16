import SwiftUI

/// 實驗:探測燈光特徵(1013)是否支援「逐顆 LED」之類的未公開命令。
/// 已知命令固定為 [模式, R, G, B],模式 1~6 = 炫彩 / 多色呼吸 / 單色呼吸 / 常亮 / 關 / 電池溫度。
/// 內建「炫彩」每顆燈顏色不同,代表燈珠本身可獨立顯示,但藍牙是否開放逐顆控制未知。
struct LightProbeView: View {
    @EnvironmentObject var ble: CoolerBLEManager
    @EnvironmentObject var light: LightController
    @State private var hex = "07 00 FF 00 00"
    @State private var mode = 7
    @State private var index = 0
    @State private var color = RGB(r: 255, g: 0, b: 0)
    @State private var withIndex = true
    @State private var history: [String] = []

    var body: some View {
        ZStack {
            AppBackground(accent: .orange)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    intro
                    modeProbe
                    rawSend
                    results
                }
                .padding(16)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("燈光命令探測(實驗)", systemImage: "lightbulb.max.fill").font(.headline).foregroundStyle(.yellow)
            Text("已知的燈光命令只能整條燈同色。這裡讓你直接往燈光特徵(1013)寫入自訂位元組,看看有沒有未公開的逐顆控制。固件對未知命令的反應不可預期(原版就記錄過某個查詢位元組會讓燈直接關掉),任何異常都可以用下方「恢復」還原。")
                .font(.footnote).foregroundStyle(.white.opacity(0.85))
        }
        .foregroundStyle(.white).glassCard(tint: .orange)
    }

    private var modeProbe: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("逐一試模式位元組").font(.headline)
            Text("格式:[模式, (編號), R, G, B]。把模式從 7 往上逐個試,觀察燈有沒有出現新的效果。")
                .font(.caption).foregroundStyle(.white.opacity(0.6))
            Stepper("模式 0x\(String(format: "%02X", mode))(\(mode))", value: $mode, in: 0...63)
            Toggle("多帶一個「燈珠編號」位元組", isOn: $withIndex)
            if withIndex { Stepper("燈珠編號 \(index)", value: $index, in: 0...63) }
            ColorPicker("顏色", selection: rgbBinding($color), supportsOpacity: false)
            GlassGroup {
                FlowRow {
                    GlassChip(title: "傳送", symbol: "paperplane.fill", selected: true, tint: .orange) {
                        var bytes: [UInt8] = [UInt8(mode)]
                        if withIndex { bytes.append(UInt8(index)) }
                        bytes += [color.r, color.g, color.b]
                        send(bytes)
                    }
                    GlassChip(title: "下一個模式", symbol: "forward.fill") {
                        mode = min(mode + 1, 63)
                        var bytes: [UInt8] = [UInt8(mode)]
                        if withIndex { bytes.append(UInt8(index)) }
                        bytes += [color.r, color.g, color.b]
                        send(bytes)
                    }
                    GlassChip(title: "恢復(常亮白)", symbol: "arrow.uturn.backward") {
                        light.applyHardware(.solid, color: .white)
                        history.append("↩︎ 已恢復常亮白")
                    }
                    GlassChip(title: "恢復(炫彩)", symbol: "sparkles") {
                        light.applyHardware(.colorful)
                        history.append("↩︎ 已恢復炫彩")
                    }
                }
            }
        }
        .foregroundStyle(.white).glassCard()
    }

    private var rawSend: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("自訂十六進位").font(.headline)
            TextField("例如 07 00 FF 00 00", text: $hex)
                .textInputAutocapitalization(.characters).autocorrectionDisabled()
                .font(.system(.body, design: .monospaced))
                .padding(12).glass(RoundedRectangle(cornerRadius: 16, style: .continuous))
            GlassGroup {
                HStack {
                    GlassChip(title: "傳送", symbol: "paperplane") {
                        if let b = parse(hex) { send(b) } else { history.append("✗ 十六進位格式不正確(需偶數個字元,最多 20 位元組)") }
                    }
                    GlassChip(title: "讀取 1013", symbol: "arrow.down.doc") {
                        ble.readValue(.light)
                        history.append("→ 讀取 1013 …")
                    }
                }
            }
            Text("1013 目前值:\(ble.lastLightRaw ?? "尚未讀到(可能不支援讀取)")")
                .font(.system(.footnote, design: .monospaced)).foregroundStyle(.white.opacity(0.75))
        }
        .foregroundStyle(.white).glassCard()
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("傳送記錄").font(.headline)
            if history.isEmpty { Text("尚無").font(.footnote).foregroundStyle(.white.opacity(0.6)) }
            ForEach(Array(history.suffix(30).reversed().enumerated()), id: \.offset) { _, line in
                Text(line).font(.system(.footnote, design: .monospaced))
            }
            if let e = ble.lastWriteError { Text("最近寫入錯誤:\(e)").font(.caption).foregroundStyle(.red.opacity(0.9)) }
            Text("提示:把「哪個模式 / 位元組讓燈有變化」記下來告訴我,我就能據此做出真正的逐顆控制。")
                .font(.caption).foregroundStyle(.white.opacity(0.55))
        }
        .foregroundStyle(.white).glassCard()
    }

    private func send(_ bytes: [UInt8]) {
        light.stop()    // 停掉動態燈效,避免干擾
        ble.lastWriteError = nil
        ble.writeRaw(.light, Data(bytes), label: "探測:\(bytes.map { String(format: "%02X", $0) }.joined(separator: " "))")
        history.append("→ " + bytes.map { String(format: "%02X", $0) }.joined(separator: " "))
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if let e = ble.lastWriteError { history.append("  ✗ 寫入失敗:\(e)") } else { history.append("  ✓ 設備已確認寫入") }
        }
    }

    private func parse(_ s: String) -> [UInt8]? {
        let clean = s.replacingOccurrences(of: "0x", with: "", options: .caseInsensitive)
            .filter { $0.isHexDigit }
        guard clean.count >= 2, clean.count % 2 == 0, clean.count <= 40 else { return nil }
        var out: [UInt8] = [], i = clean.startIndex
        while i < clean.endIndex {
            let j = clean.index(i, offsetBy: 2)
            guard let b = UInt8(clean[i..<j], radix: 16) else { return nil }
            out.append(b); i = j
        }
        return out
    }
}
