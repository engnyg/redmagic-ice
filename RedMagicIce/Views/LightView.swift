import SwiftUI

struct LightView: View {
    @EnvironmentObject var ble: CoolerBLEManager
    @EnvironmentObject var light: LightController
    @State private var editing = false

    private var active: LightController.Active { light.active }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hardwareSection
                softwareSection
                linkSection
                tuneSection
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
        }
    }

    // MARK: 硬體燈效(裝置內建,App 退出後仍然保持)
    private var hardwareSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("裝置內建燈效")
            GlassGroup {
                FlowRow {
                    ForEach(HardwareLight.allCases) { k in
                        GlassChip(title: k.title, symbol: k.symbol, selected: active == .hardware(k), tint: .orange) {
                            light.applyHardware(k)
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("顏色").font(.headline)
                    Spacer()
                    ColorPicker("自定義", selection: rgbBinding($light.settings.solid), supportsOpacity: false)
                        .labelsHidden()
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 10) {
                    ForEach(CoolerProtocol.lightPresets) { p in
                        let c = RGB(r: p.r, g: p.g, b: p.b)
                        Circle().fill(c.color).frame(height: 38)
                            .overlay(Circle().stroke(Color.white.opacity(light.settings.solid == c ? 0.95 : 0.25), lineWidth: light.settings.solid == c ? 3 : 1))
                            .onTapGesture { light.applyHardware(.solid, color: c) }
                            .onLongPressGesture { light.applyHardware(.breathMono, color: c) }
                            .accessibilityLabel(p.name)
                    }
                }
                Text("點按=常亮,長按=單色呼吸。也可用右上角取色器選任意顏色。")
                    .font(.caption).foregroundStyle(.white.opacity(0.6))
            }
            .foregroundStyle(.white).glassCard()
        }
    }

    // MARK: 軟體燈效(App 逐幀驅動)
    private var softwareSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("動態燈效(App 驅動)")
            GlassGroup {
                FlowRow {
                    ForEach(SoftwareEffect.allCases) { e in
                        GlassChip(title: e.title, symbol: e.symbol, selected: active == .software(e), tint: .pink) {
                            light.start(e)
                        }
                    }
                }
            }
            if case .software(let e) = active, e.usesColorList || e.usesSolidColor {
                VStack(alignment: .leading, spacing: 12) {
                    if e.usesSolidColor {
                        ColorPicker("主色", selection: rgbBinding($light.settings.solid), supportsOpacity: false)
                    } else {
                        colorListEditor
                    }
                }
                .foregroundStyle(.white).glassCard()
            }
            Text("裝置韌體只有 6 種內建燈效;動態燈效由 App 每 0.6 秒以上傳送一幀顏色模擬,需保持 App 在前臺。")
                .font(.caption).foregroundStyle(.white.opacity(0.55)).padding(.horizontal, 6)
        }
    }

    private var colorListEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("顏色序列").font(.headline)
            ForEach(Array(light.settings.colors.enumerated()), id: \.offset) { i, _ in
                HStack {
                    ColorPicker("顏色 \(i + 1)", selection: rgbBinding($light.settings.colors[i]), supportsOpacity: false)
                    if light.settings.colors.count > 1 {
                        Button { light.settings.colors.remove(at: i) } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red.opacity(0.85))
                        }.buttonStyle(.plain)
                    }
                }
            }
            if light.settings.colors.count < 8 {
                GlassChip(title: "新增顏色", symbol: "plus") {
                    light.settings.colors.append(.hsv(Double(light.settings.colors.count) * 47, 1, 1))
                }
            }
        }
    }

    // MARK: 聯動
    private var linkSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("聯動燈效")
            GlassGroup {
                FlowRow {
                    GlassChip(title: "溫度聯動", symbol: "thermometer.sun.fill", selected: active == .tempLinked, tint: .orange) {
                        light.startTempLinked()
                    }
                    GlassChip(title: "檔位聯動", symbol: "chart.bar.fill", selected: active == .levelLinked, tint: .blue) {
                        light.startLevelLinked()
                    }
                    GlassChip(title: "模式聯動", symbol: "link", selected: active == .modeLinked, tint: .green) {
                        light.startModeLinked()
                    }
                }
            }
            if active == .modeLinked {
                VStack(alignment: .leading, spacing: 14) {
                    linkRow("手動 / 待機", $light.settings.linkManual)
                    linkRow("智慧溫控", $light.settings.linkSmart)
                    linkRow("破壞神", $light.settings.linkBoost)
                    linkRow("散熱關閉", $light.settings.linkOff)
                }
                .foregroundStyle(.white).glassCard()
            } else {
                Text("溫度聯動:按散熱器溫度 5 檔變色(<34 青 / <38 綠 / <42 黃 / <45 橙 / 更高紅);檔位聯動:檔位越高越紅。")
                    .font(.caption).foregroundStyle(.white.opacity(0.55)).padding(.horizontal, 6)
            }
        }
    }

    private func linkRow(_ title: String, _ link: Binding<LinkedLight>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                if link.wrappedValue.kind.usesColor {
                    ColorPicker("", selection: rgbBinding(link.color), supportsOpacity: false).labelsHidden()
                }
            }
            FlowRow {
                ForEach(HardwareLight.allCases) { k in
                    GlassChip(title: k.title, selected: link.wrappedValue.kind == k, tint: .green) {
                        link.wrappedValue.kind = k
                        light.startModeLinked()
                    }
                }
            }
        }
    }

    // MARK: 亮度 / 速度
    private var tuneSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Image(systemName: "sun.max.fill"); Slider(value: $light.settings.brightness, in: 0.05...1) }
            HStack {
                Image(systemName: "hare.fill")      // 左=快
                Slider(value: $light.settings.speed, in: LightSettings.minInterval(fast: light.settings.isFast)...2.0) { editing in
                    if !editing { light.speedChanged() }
                }
                Image(systemName: "tortoise.fill")  // 右=慢(2 秒)
            }
            HStack {
                Text(String(format: "每 %.1f 秒 1 幀", light.settings.speed))
                Spacer()
                if case .software = active { Text(String(format: "實際約 %.1f 幀/秒", light.measuredFPS)) }
            }
            .font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.75))
            Toggle("快速燈效(實驗)", isOn: Binding(get: { light.settings.isFast }, set: { light.setFastMode($0) }))
            if light.settings.isFast {
                Text(ble.lightNoResponseSupported
                     ? "此散熱器的燈光特徵支援免回覆寫入,快速模式會直接送出,最快每 0.1 秒一幀。若出現卡頓、調檔變慢或斷線,請關閉此開關。"
                     : "此散熱器的燈光特徵不支援免回覆寫入,每幀仍須等設備回覆,實際幀率會低於設定值。若出現卡頓、調檔變慢或斷線,請關閉此開關。")
                    .font(.caption).foregroundStyle(.yellow.opacity(0.85))
            }
            HStack {
                Text("亮度對動態燈效、常亮/呼吸顏色生效;速度僅對動態燈效生效。")
                    .font(.caption).foregroundStyle(.white.opacity(0.6))
                Spacer()
                if active != .none { GlassChip(title: "停止", symbol: "stop.fill") { light.stop() } }
            }
        }
        .foregroundStyle(.white).glassCard()
    }
}

/// 簡單的自動換行容器
struct FlowRow<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        if #available(iOS 16.0, *) {
            FlowLayout(spacing: 10) { content() }
        } else {
            HStack { content() }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 10
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal.width ?? 320, subviews).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let r = arrange(bounds.width, subviews)
        for (i, p) in r.points.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + p.x, y: bounds.minY + p.y), proposal: .unspecified)
        }
    }
    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (points: [CGPoint], size: CGSize) {
        var pts: [CGPoint] = [], x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxW: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > 0 && x + sz.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            pts.append(CGPoint(x: x, y: y))
            x += sz.width + spacing; rowH = max(rowH, sz.height); maxW = max(maxW, x - spacing)
        }
        return (pts, CGSize(width: maxW, height: y + rowH))
    }
}
