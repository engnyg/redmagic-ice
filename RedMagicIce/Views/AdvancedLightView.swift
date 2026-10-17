import SwiftUI

/// 進階燈效:逐顆燈珠 + 固件內建新燈效(紅魔 8 Pro · 固件 8.5.2 / 8.5.3)
struct AdvancedLightView: View {
    @EnvironmentObject var ble: CoolerBLEManager
    @EnvironmentObject var fw: FirmwareLightController
    @Environment(\.dismiss) private var dismiss
    @State private var selected = 0
    @State private var previewMode = false

    var body: some View {
        ZStack {
            AppBackground(accent: .pink)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    capabilityCard
                    if !fw.consent { consentCard } else {
                        pixelCard
                        effectCard
                    }
                }
                .padding(16)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: 支援狀態
    private var capabilityCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("進階燈效(實驗)", systemImage: "sparkles").font(.headline).foregroundStyle(.yellow)
            Text("16 顆燈珠可各自設定顏色,另有 8 種由散熱器自己運行的內建新燈效。這是固件功能:需要紅魔 8 Pro,並已刷入 8.5.2 / 8.5.3 固件才有。")
                .font(.footnote).foregroundStyle(.white.opacity(0.8))
            row("機型", ble.connected ? ble.modelTitle : "未連線")
            row("主控固件", ble.mainFirmware.isEmpty ? "尚未讀到" : ble.mainFirmware)
            if ble.connected {
                if ble.supportsFirmwareLight {
                    Label("此裝置支援", systemImage: "checkmark.seal.fill").foregroundStyle(.green).font(.footnote.weight(.semibold))
                } else {
                    Label("此裝置不支援,下方控制已停用", systemImage: "xmark.seal.fill").foregroundStyle(.orange).font(.footnote.weight(.semibold))
                    Text("本 App 無法刷寫固件。固件需自行取得並以 Telink OTA 工具刷入,過程有風險(可能失去保固、需要重刷,極端情況下損壞設備),請自行評估。")
                        .font(.caption).foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .foregroundStyle(.white).glassCard(tint: .pink)
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack { Text(k).foregroundStyle(.white.opacity(0.7)); Spacer(); Text(v).monospacedDigit() }.font(.footnote)
    }

    private var consentCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("使用前請閱讀").font(.headline)
            Text("• 這是第三方的實驗性擴充功能,不是紅魔或努比亞發佈、認證的官方功能,不同硬體批次可能有差異。\n• 持續高亮、接近白色、大面積同時點亮、逐顆快速變化,可能增加燈帶、驅動、電源與主控的負擔,出現閃爍、顏色鎖死、無法熄滅、異常發熱、斷線、需要重刷固件,極端情況下不能排除硬體損壞。\n• App 對自訂顏色加了保守上限(單顆 RGB 總和不超過 382,亮度上限位元組不超過 127),但這只是降低風險,不是安全保證,也不能測量燈珠溫度。\n• 若燈光卡住或異常,請停止使用並關閉燈光;仍異常就斷開散熱器供電,必要時恢復官方固件。\n• 使用本功能的風險由你自行承擔。")
                .font(.footnote).foregroundStyle(.white.opacity(0.85))
            GlassChip(title: "我已閱讀並了解風險,繼續", symbol: "checkmark", selected: true, tint: .pink) { fw.consent = true }
        }
        .foregroundStyle(.white).glassCard()
    }

    // MARK: 逐顆燈珠
    private var pixelCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("逐顆燈珠").font(.headline)
            Text("點選圓環上的燈珠,再用下方取色器上色。燈珠編號依硬體排列而定,先試試看再對應實際位置。")
                .font(.footnote).foregroundStyle(.white.opacity(0.7))
            Picker("", selection: $previewMode) {
                Text("編輯燈珠").tag(false)
                Text("預覽燈效").tag(true)
            }
            .pickerStyle(.segmented)
            if previewMode {
                ringEffectPreview
            } else {
                ring
            }
            HStack {
                Text("燈珠 \(selected + 1)").font(.subheadline.weight(.semibold))
                Spacer()
                ColorPicker("", selection: pixelBinding(selected), supportsOpacity: false).labelsHidden()
            }
            GlassGroup {
                FlowRow {
                    GlassChip(title: "彩虹環", symbol: "rainbow") { fw.setRainbow(); fw.schedulePixels() }
                    GlassChip(title: "全部同色", symbol: "circle.fill") { fw.setAllPixels(fw.stored.pixels[selected]); fw.schedulePixels() }
                    GlassChip(title: "對半", symbol: "circle.lefthalf.filled") {
                        fw.setHalves(fw.stored.pixels[selected], fw.stored.pixels[(selected + 8) % 16]); fw.schedulePixels()
                    }
                    GlassChip(title: "全黑", symbol: "circle") { fw.setAllPixels(.black); fw.schedulePixels() }
                }
            }
            HStack { Image(systemName: "sun.max.fill")
                Slider(value: Binding(get: { Double(fw.stored.pixelBrightness) }, set: { fw.stored.pixelBrightness = Int($0) }), in: 5...100, step: 1) { e in
                    if !e { fw.schedulePixels() }
                }
                Text("\(fw.stored.pixelBrightness)%").font(.footnote.monospacedDigit()).frame(width: 44)
            }
            Toggle("調整時即時套用", isOn: $fw.liveApply)
            GlassGroup {
                HStack {
                    GlassChip(title: "套用到散熱器", symbol: "paperplane.fill", selected: true, tint: .pink) { fw.applyPixels() }
                    GlassChip(title: "停止並還原", symbol: "stop.fill") { fw.stopFirmwareLight() }
                }
            }
            statusLine
        }
        .foregroundStyle(.white).glassCard()
        .disabled(!ble.supportsFirmwareLight)
        .opacity(ble.supportsFirmwareLight ? 1 : 0.5)
    }

    private var ring: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, 280)
            let r = size / 2 - 22
            ZStack {
                ForEach(0..<FirmwareLight.ledCount, id: \.self) { i in
                    let a = -Double.pi / 2 + Double(i) * 2 * .pi / Double(FirmwareLight.ledCount)
                    Circle().fill(fw.stored.pixels.indices.contains(i) ? fw.stored.pixels[i].color : .clear)
                        .frame(width: 30, height: 30)
                        .overlay(Circle().stroke(Color.white.opacity(selected == i ? 1 : 0.25), lineWidth: selected == i ? 3 : 1))
                        .overlay(Text("\(i + 1)").font(.system(size: 10, weight: .bold)).foregroundStyle(.black.opacity(0.55)))
                        .position(x: geo.size.width / 2 + CGFloat(cos(a)) * r, y: size / 2 + CGFloat(sin(a)) * r)
                        .onTapGesture { selected = i }
                }
            }
        }
        .frame(height: 280)
    }

    private func pixelBinding(_ i: Int) -> Binding<Color> {
        Binding(get: { fw.stored.pixels.indices.contains(i) ? fw.stored.pixels[i].color : .clear },
                set: { if fw.stored.pixels.indices.contains(i) { fw.stored.pixels[i] = RGB($0); fw.schedulePixels() } })
    }

    /// 調色盤顏色數會隨切換燈效或按「−」改變,SwiftUI 可能用舊的索引去讀剛縮短的陣列而閃退,所以一律檢查範圍。
    private func paletteBinding(_ i: Int) -> Binding<Color> {
        Binding(get: { fw.stored.palette.indices.contains(i) ? fw.stored.palette[i].color : .clear },
                set: { if fw.stored.palette.indices.contains(i) { fw.stored.palette[i] = RGB($0) } })
    }

    // MARK: 內建燈效
    private var effectCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("固件內建燈效").font(.headline)
            Text("設定一次後由散熱器自己運行,不需要 App 一直傳資料,App 關閉後也不會停。")
                .font(.footnote).foregroundStyle(.white.opacity(0.7))
            GlassGroup {
                FlowRow {
                    ForEach(FirmwareLight.effects) { e in
                        GlassChip(title: e.name, selected: fw.stored.effect == e.id, tint: .pink) { fw.chooseEffect(e.id) }
                    }
                }
            }
            effectPreview
            VStack(alignment: .leading, spacing: 8) {
                Text("配色").font(.subheadline.weight(.semibold))
                ForEach(Array(fw.stored.palette.indices), id: \.self) { i in
                    HStack {
                        ColorPicker("顏色 \(i + 1)", selection: paletteBinding(i), supportsOpacity: false)
                        if fw.stored.palette.count > 1 {
                            Button { if fw.stored.palette.indices.contains(i) { fw.stored.palette.remove(at: i) } } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(.red.opacity(0.85))
                            }.buttonStyle(.plain)
                        }
                    }
                }
                if fw.stored.palette.count < 8 {
                    GlassChip(title: "新增顏色", symbol: "plus") { fw.stored.palette.append(.hsv(Double(fw.stored.palette.count) * 47, 1, 1)) }
                }
            }
            HStack { Image(systemName: "tortoise.fill")
                Slider(value: Binding(get: { Double(fw.stored.speed) }, set: { fw.stored.speed = Int($0) }), in: 0...100, step: 1)
                Image(systemName: "hare.fill")
            }
            HStack { Image(systemName: "sun.max.fill")
                Slider(value: Binding(get: { Double(fw.stored.effectBrightness) }, set: { fw.stored.effectBrightness = Int($0) }), in: 5...100, step: 1)
                Text("\(fw.stored.effectBrightness)%").font(.footnote.monospacedDigit()).frame(width: 44)
            }
            GlassGroup {
                HStack {
                    GlassChip(title: "啟動燈效", symbol: "play.fill", selected: true, tint: .pink) { fw.startEffect() }
                    GlassChip(title: "停止並還原", symbol: "stop.fill") { fw.stopFirmwareLight() }
                }
            }
            statusLine
        }
        .foregroundStyle(.white).glassCard()
        .disabled(!ble.supportsFirmwareLight)
        .opacity(ble.supportsFirmwareLight ? 1 : 0.5)
    }

    /// 逐顆燈珠卡片裡的「預覽燈效」:整圈播放目前選的內建燈效(與下方「固件內建燈效」同一份設定)。
    private var ringEffectPreview: some View {
        let e = fw.stored.effect
        return VStack(spacing: 6) {
            TimelineView(.animation) { ctx in
                let colors = FirmwareEffectSimulator.frame(effect: e, palette: fw.stored.palette, speed: fw.stored.speed,
                                                           brightness: fw.stored.effectBrightness,
                                                           time: ctx.date.timeIntervalSinceReferenceDate)
                RingPreview(colors: colors).frame(height: 280)
            }
            let name = FirmwareLight.effects.first { $0.id == e }?.name ?? ""
            Text("預覽:\(name)(到下方「固件內建燈效」換效果、配色、速度)")
                .font(.caption).foregroundStyle(.white.opacity(0.7))
            Text(FirmwareEffectSimulator.exactEffects.contains(e) ? "依韌體結構模擬" : "這個效果只是外觀近似,實機可能不同")
                .font(.caption2).foregroundStyle(.white.opacity(0.5))
            if case .effect(let running)? = fw.active, let rn = FirmwareLight.effects.first(where: { $0.id == running })?.name {
                Text("散熱器目前執行:\(rn)").font(.caption2).foregroundStyle(.green.opacity(0.9))
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// 依目前選的燈效、配色、速度、亮度在畫面上模擬(不會送給設備),調整時即時更新。
    private var effectPreview: some View {
        let e = fw.stored.effect
        return VStack(spacing: 6) {
            TimelineView(.animation) { ctx in
                let colors = FirmwareEffectSimulator.frame(effect: e, palette: fw.stored.palette, speed: fw.stored.speed,
                                                           brightness: fw.stored.effectBrightness,
                                                           time: ctx.date.timeIntervalSinceReferenceDate)
                RingPreview(colors: colors).frame(height: 150)
            }
            Text(FirmwareEffectSimulator.exactEffects.contains(e)
                 ? "預覽:依韌體結構模擬,實機動作應該相同"
                 : "預覽:這個效果只是外觀近似,實機可能不同")
                .font(.caption2).foregroundStyle(.white.opacity(0.55))
            if case .effect(let running)? = fw.active, let name = FirmwareLight.effects.first(where: { $0.id == running })?.name {
                Text("散熱器目前執行:\(name)").font(.caption2).foregroundStyle(.green.opacity(0.9))
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var statusLine: some View {
        if ble.queueDepth > 1 {
            HStack { ProgressView(); Text("傳送中,剩 \(ble.queueDepth) 筆…") }.font(.caption).foregroundStyle(.white.opacity(0.7))
        } else if !fw.status.isEmpty {
            Text(fw.status).font(.caption).foregroundStyle(.yellow.opacity(0.9))
        }
    }
}

/// 16 顆燈珠排成一圈的小預覽。
struct RingPreview: View {
    let colors: [RGB]
    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let r = size / 2 - 12
            ZStack {
                ForEach(0..<FirmwareLight.ledCount, id: \.self) { i in
                    let a = -Double.pi / 2 + Double(i) * 2 * .pi / Double(FirmwareLight.ledCount)
                    let c = colors.indices.contains(i) ? colors[i] : .black
                    Circle().fill(c == .black ? Color.white.opacity(0.08) : c.color)
                        .frame(width: 18, height: 18)
                        .shadow(color: c == .black ? .clear : c.color.opacity(0.9), radius: 6)
                        .position(x: geo.size.width / 2 + CGFloat(cos(a)) * r, y: geo.size.height / 2 + CGFloat(sin(a)) * r)
                }
            }
        }
    }
}
