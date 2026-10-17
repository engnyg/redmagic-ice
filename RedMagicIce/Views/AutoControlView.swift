import SwiftUI

struct AutoControlView: View {
    @EnvironmentObject var ble: CoolerBLEManager
    @EnvironmentObject var auto: AutoController
    @State private var kind: AutoKind = .free

    var body: some View {
        ZStack {
            AppBackground(accent: .mint)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    statusCard
                    GlassGroup {
                        FlowRow {
                            ForEach(AutoKind.allCases) { k in
                                GlassChip(title: k.title, symbol: k.symbol, selected: kind == k, tint: .mint) { kind = k }
                            }
                        }
                    }
                    switch kind {
                    case .free: freeCard
                    case .battery: batteryCard
                    case .target: targetCard
                    }
                    intervalCard
                }
                .padding(16)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { if let a = auto.active { kind = a } }
    }

    // MARK: 狀態 / 啟停
    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(auto.active.map { "進行中:\($0.title)" } ?? "自動溫控未啟用").font(.headline)
                Spacer()
                if let l = auto.currentLevel { Text("\(l + 1) 檔").font(.title3.weight(.semibold)).monospacedDigit() }
            }
            Text(auto.status.isEmpty ? "選擇下方模式後按「啟用」。啟用時會自動關閉智慧溫控與破壞神,改由 App 依溫度調整 1~10 檔。" : auto.status)
                .font(.footnote).foregroundStyle(.white.opacity(0.75))
            GlassGroup {
                HStack {
                    if auto.active == kind {
                        GlassChip(title: "停止", symbol: "stop.fill", selected: true, tint: .red) { auto.stop() }
                    } else {
                        GlassChip(title: "啟用\(kind.title)", symbol: "play.fill", selected: true, tint: .mint) { auto.start(kind) }
                            .disabled(!ble.connected)
                    }
                }
            }
            if !ble.connected { Text("未連線散熱器,無法啟用。").font(.caption).foregroundStyle(.orange) }
        }
        .foregroundStyle(.white).glassCard(tint: auto.active == nil ? nil : .mint)
    }

    // MARK: 自由變頻
    private var freeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("自由變頻").font(.headline)
            Text("依散熱背夾(散熱器)溫度自動調整檔位。散熱器溫度越高代表手機負載越大,檔位就越高。共 3 組預設曲線,每組 11 個點,可拖曳圓點自訂溫度與檔位;目標檔位與目前檔位相差不到 0.55 時保持不動,避免頻繁切換。")
                .font(.footnote).foregroundStyle(.white.opacity(0.7))
            GlassGroup {
                FlowRow {
                    ForEach(0..<3, id: \.self) { i in
                        GlassChip(title: TempCurve.presetNames[i], selected: auto.settings.activePreset == i, tint: .mint) {
                            auto.settings.activePreset = i
                        }
                    }
                }
            }
            CurveEditor(curve: $auto.settings.activeFreeCurve, range: -30...40,
                        currentTemp: ble.temperatureC.map(Double.init), maxLevel: auto.settings.allowAutoBoost ? 11 : 10)
            GlassChip(title: "恢復此組預設曲線", symbol: "arrow.counterclockwise") {
                auto.settings.activeFreeCurve = TempCurve.factoryPresets[auto.settings.activePreset]
            }
            boostToggle
        }
        .foregroundStyle(.white).glassCard()
    }

    private var boostToggle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("必要時自動啟用破壞神", isOn: Binding(get: { auto.settings.allowAutoBoost }, set: { auto.settings.allowAutoBoost = $0 }))
            Text("開啟後曲線可拉到第 11 檔(破壞神):需求超過 10.65 檔並持續 1.6 秒才進入,降到 10 檔以下並持續 2.8 秒才退出。破壞神發熱與噪音大,預設關閉。")
                .font(.caption).foregroundStyle(.white.opacity(0.55))
        }
    }

    // MARK: 電池溫控
    private var batteryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("電池溫控").font(.headline)
            Text("依手機溫度自動調整檔位,兼顧降溫與日常穩定。")
                .font(.footnote).foregroundStyle(.white.opacity(0.7))
            VStack(alignment: .leading, spacing: 6) {
                Label("iOS 不開放電池溫度", systemImage: "exclamationmark.triangle.fill").font(.footnote.weight(.semibold)).foregroundStyle(.yellow)
                Text("這裡改用系統「熱狀態」估算:正常≈33°C、輕微發熱≈38°C、嚴重發熱≈44°C、危急≈50°C,再套用下方曲線。數值是估算,不是真實溫度;也可切到「手動模擬」自己指定溫度。")
                    .font(.caption).foregroundStyle(.white.opacity(0.7))
            }
            GlassGroup {
                FlowRow {
                    ForEach(BatterySource.allCases) { s in
                        GlassChip(title: s.title, selected: auto.settings.batterySource == s, tint: .mint) { auto.settings.batterySource = s }
                    }
                }
            }
            if auto.settings.batterySource == .simulated {
                HStack {
                    Text("模擬溫度")
                    Slider(value: $auto.settings.simulatedBattery, in: 25...55, step: 0.5)
                    Text(String(format: "%.1f°C", auto.settings.simulatedBattery)).monospacedDigit()
                }
            } else {
                let s = ProcessInfo.processInfo.thermalState
                Text("目前熱狀態:\(AutoLogic.thermalName(s))(估算 \(Int(AutoLogic.estimatedTemp(s)))°C)")
                    .font(.footnote.monospacedDigit()).foregroundStyle(.white.opacity(0.85))
            }
            CurveEditor(curve: $auto.settings.batteryCurve, range: 25...55, currentTemp: auto.batteryTemp(),
                        maxLevel: auto.settings.allowAutoBoost ? 11 : 10)
            GlassChip(title: "恢復官方曲線", symbol: "arrow.counterclockwise") { auto.settings.batteryCurve = .batteryDefault }
            boostToggle
        }
        .foregroundStyle(.white).glassCard()
    }

    // MARK: 目標溫度
    private var targetCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("目標溫度控制").font(.headline)
            Text("設定散熱器目標溫度,App 會自動調整檔位,盡量把散熱器維持在目標附近。內建溫控穩定器:取最近 3 筆中位數再平滑,升檔最多一次 2 檔、降檔一次 1 檔,並有遲滯與最短停留時間,避免來回跳動;目標 5°C 以下且超出 1°C 時直接滿檔。")
                .font(.footnote).foregroundStyle(.white.opacity(0.7))
            HStack {
                Text("目標").foregroundStyle(.white.opacity(0.8))
                Slider(value: $auto.settings.targetTemp, in: 0...30, step: 0.5)
                Text(String(format: "%.1f°C", auto.settings.targetTemp))
                    .font(.title3.weight(.semibold).monospacedDigit()).frame(width: 84, alignment: .trailing)
            }
            HStack {
                Text("目前散熱器溫度").foregroundStyle(.white.opacity(0.8))
                Spacer()
                Text(ble.temperatureC.map { String(format: "%.1f°C", $0) } ?? "--").monospacedDigit()
            }
            .font(.footnote)
            Text("需求檔位依超出目標的溫度而定:0.4°C→2 檔、0.8→3、1.5→5、3→7、5→9、6.5→10、8 以上→破壞神(需開啟自動啟用)。接近目標時維持基本檔位,目標越低基本檔位越高。")
                .font(.caption).foregroundStyle(.white.opacity(0.55))
            boostToggle
        }
        .foregroundStyle(.white).glassCard()
    }

    private var intervalCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("評估間隔")
                Slider(value: $auto.settings.interval, in: 3...20, step: 1)
                Text("\(Int(auto.settings.interval)) 秒").monospacedDigit()
            }
            Text("App 在前台時依間隔評估;退到背景後,只有藍牙收到散熱器新溫度時才會評估,iOS 可能暫停背景執行,長時間自動控溫請保持 App 開啟。")
                .font(.caption).foregroundStyle(.white.opacity(0.55))
        }
        .foregroundStyle(.white).glassCard()
    }
}
