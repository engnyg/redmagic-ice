import SwiftUI
import PhotosUI

extension CoolerBLEManager {
    /// 主題色:隨工作模式變化
    var accent: Color {
        guard connected, running else { return .indigo }
        switch mode {
        case .boost: return .red
        case .smart: return .green
        case .manual: return .cyan
        case .idle: return .blue
        }
    }
}

extension View {
    /// TabView 的分頁容器可能遮住底層背景,所以每個分頁自己畫一次背景。
    func appPage(_ accent: Color) -> some View { self.background(AppBackground(accent: accent)) }
}

struct RootView: View {
    @EnvironmentObject var ble: CoolerBLEManager

    var body: some View {
        ZStack {
            AppBackground(accent: ble.accent)
            if ble.connected || ble.offlinePreview {
                TabView {
                    ControlView().appPage(ble.accent).tabItem { Label("控制", systemImage: "fanblades.fill") }
                    LightView().appPage(ble.accent).tabItem { Label("燈光", systemImage: "lightbulb.led.fill") }
                    MoreView().appPage(ble.accent).tabItem { Label("更多", systemImage: "ellipsis.circle") }
                }
            } else {
                ScanView()
            }
        }
    }
}

struct ScanView: View {
    @EnvironmentObject var ble: CoolerBLEManager
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Spacer(minLength: 60)
                Image("Logo").resizable().scaledToFit()
                    .frame(width: 168, height: 168)
                    .shadow(color: .cyan.opacity(0.45), radius: 24)
                VStack(spacing: 4) {
                    Text("極凍").font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    Text("CRYO · 散熱器控制").font(.caption.weight(.semibold)).tracking(2).foregroundStyle(.white.opacity(0.6))
                }
                if ble.state != .poweredOn {
                    Text("請在系統設定中開啟藍牙並允許本 App 使用藍牙")
                        .font(.footnote).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center)
                }
                GlassChip(title: ble.scanning ? "掃描中…" : "掃描散熱器", symbol: "dot.radiowaves.left.and.right",
                          selected: ble.scanning, tint: .cyan) { ble.startScan() }
                    .disabled(ble.state != .poweredOn || ble.scanning)
                GlassChip(title: "不連線,先看看介面", symbol: "eye") { ble.offlinePreview = true }
                GlassGroup {
                    VStack(spacing: 10) {
                        ForEach(ble.discovered) { d in
                            Button { ble.connect(d) } label: {
                                HStack {
                                    Image(systemName: "fanblades")
                                    Text(d.name).fontWeight(.semibold)
                                    Spacer()
                                    Text("\(d.rssi) dBm").foregroundStyle(.white.opacity(0.6)).font(.footnote)
                                }
                                .foregroundStyle(.white).padding(16)
                            }
                            .buttonStyle(.plain)
                            .glass(RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: true)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

struct MoreView: View {
    @EnvironmentObject var ble: CoolerBLEManager
    @EnvironmentObject var appearance: AppearanceController
    @EnvironmentObject var live: LiveActivityController
    @EnvironmentObject var memory: MemoryController
    @State private var showLog = false
    @State private var showLab = false
    @State private var showProbe = false
    @State private var pickedPhoto: PhotosPickerItem?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle("外觀")
                appearanceCard
                SectionTitle("動態島")
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("動態島 / 鎖屏即時動態", isOn: $live.enabled)
                    Text(live.systemAllowed
                         ? "連線後自動在動態島顯示溫度,長按展開可看轉速與功率。"
                         : "系統已關閉即時動態:請到 設定 → 極凍 → 即時動態 開啟。")
                        .font(.caption).foregroundStyle(.white.opacity(0.6))
                }.foregroundStyle(.white).glassCard()
                SectionTitle("記憶")
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("記憶上次狀態", isOn: $memory.enabled)
                    Toggle("連線後自動恢復模式與燈效", isOn: $memory.autoRestore).disabled(!memory.enabled)
                    Text("上次模式:\(memory.lastMode?.title ?? "尚無")")
                        .font(.footnote).foregroundStyle(.white.opacity(0.75))
                    Text("在 App 內按電源開機時,會自動回到上次的模式。連線後只有在散熱器已經運轉、且沒有任何模式時才會補上,不會替你自動開機。")
                        .font(.caption).foregroundStyle(.white.opacity(0.55))
                    GlassGroup {
                        FlowRow {
                            GlassChip(title: "立即恢復", symbol: "arrow.counterclockwise") { memory.restoreAll() }
                            GlassChip(title: "清除記憶", symbol: "trash") { memory.forget() }
                        }
                    }
                }.foregroundStyle(.white).glassCard()
                SectionTitle("裝置")
                VStack(alignment: .leading, spacing: 8) {
                    Text(ble.deviceName).font(.headline)
                    Text(ble.firmware.isEmpty ? "韌體版本讀取中…" : "韌體 \(ble.firmware)")
                        .font(.footnote).foregroundStyle(.white.opacity(0.65))
                }.foregroundStyle(.white).glassCard()
                GlassGroup {
                    FlowRow {
                        GlassChip(title: "通訊日誌", symbol: "doc.text") { showLog = true }
                        GlassChip(title: "超頻探測(實驗)", symbol: "flame") { showLab = true }
                        GlassChip(title: "燈光命令探測(實驗)", symbol: "lightbulb.max") { showProbe = true }
                        if ble.connected {
                            GlassChip(title: "斷開連線", symbol: "bolt.slash.fill", selected: true, tint: .red) { ble.disconnect() }
                        } else {
                            GlassChip(title: "返回掃描", symbol: "dot.radiowaves.left.and.right", selected: true, tint: .cyan) { ble.offlinePreview = false }
                        }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 8)
        }
        .onChange(of: pickedPhoto) { item in
            guard let item else { return }
            Task {
                let data = try? await item.loadTransferable(type: Data.self)
                await MainActor.run {
                    if let data { appearance.setPhoto(data: data) } else { appearance.message = "無法讀取這張照片,請換一張" }
                    pickedPhoto = nil
                }
            }
        }
        .sheet(isPresented: $showLab) { OverclockView() }
        .sheet(isPresented: $showProbe) { LightProbeView() }
        .sheet(isPresented: $showLog) {
            NavigationStack {
                List(Array(ble.log.reversed().enumerated()), id: \.offset) {
                    Text($0.element).font(.system(.caption, design: .monospaced))
                }
                .navigationTitle("日誌").navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}

extension MoreView {
    var appearanceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("背景").font(.headline)
            GlassGroup {
                FlowRow {
                    ForEach(AppearanceSettings.Style.allCases) { st in
                        GlassChip(title: st.title, symbol: st.symbol, selected: appearance.settings.style == st, tint: .purple) {
                            if st == .photo && appearance.photo == nil { return }   // 先選照片
                            appearance.settings.style = st
                        }
                    }
                }
            }
            switch appearance.settings.style {
            case .aurora:
                Text("極光背景會隨工作模式變色。").font(.caption).foregroundStyle(.white.opacity(0.6))
            case .solid:
                ColorPicker("背景顏色", selection: rgbBinding($appearance.settings.color1), supportsOpacity: false)
            case .gradient:
                ColorPicker("起始顏色", selection: rgbBinding($appearance.settings.color1), supportsOpacity: false)
                ColorPicker("結束顏色", selection: rgbBinding($appearance.settings.color2), supportsOpacity: false)
            case .photo:
                HStack { Image(systemName: "drop"); Slider(value: $appearance.settings.blur, in: 0...30) }
            }
            if appearance.settings.style != .aurora {
                HStack { Image(systemName: "moon.fill"); Slider(value: $appearance.settings.dim, in: 0...0.7) }
            }
            HStack {
                PhotosPicker(selection: $pickedPhoto, matching: .images) {
                    Label(appearance.photo == nil ? "選擇照片" : "更換照片", systemImage: "photo.on.rectangle")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                }
                .glass(Capsule(), interactive: true)
                if appearance.photo != nil {
                    GlassChip(title: "刪除照片", symbol: "trash") { appearance.removePhoto() }
                }
            }
            if let m = appearance.message { Text(m).font(.caption).foregroundStyle(.yellow.opacity(0.9)) }
        }
        .foregroundStyle(.white).glassCard()
    }
}
