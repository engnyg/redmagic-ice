import SwiftUI
import PhotosUI

extension CoolerBLEManager {
    /// 主题色:随工作模式变化
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

struct RootView: View {
    @EnvironmentObject var ble: CoolerBLEManager

    var body: some View {
        ZStack {
            AppBackground(accent: ble.accent)
            if ble.connected {
                TabView {
                    ControlView().tabItem { Label("控制", systemImage: "fanblades.fill") }
                    LightView().tabItem { Label("灯光", systemImage: "lightbulb.led.fill") }
                    MoreView().tabItem { Label("更多", systemImage: "ellipsis.circle") }
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
                Image(systemName: "snowflake").font(.system(size: 64, weight: .light)).foregroundStyle(.white)
                    .frame(width: 130, height: 130).glass(Circle())
                Text("冰环").font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(.white)
                if ble.state != .poweredOn {
                    Text("请在系统设置中开启蓝牙并允许本 App 使用蓝牙")
                        .font(.footnote).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center)
                }
                GlassChip(title: ble.scanning ? "扫描中…" : "扫描散热器", symbol: "dot.radiowaves.left.and.right",
                          selected: ble.scanning, tint: .cyan) { ble.startScan() }
                    .disabled(ble.state != .poweredOn || ble.scanning)
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
    @State private var showLog = false
    @State private var pickedPhoto: PhotosPickerItem?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle("外观")
                appearanceCard
                SectionTitle("设备")
                VStack(alignment: .leading, spacing: 8) {
                    Text(ble.deviceName).font(.headline)
                    Text(ble.firmware.isEmpty ? "固件版本读取中…" : "固件 \(ble.firmware)")
                        .font(.footnote).foregroundStyle(.white.opacity(0.65))
                }.foregroundStyle(.white).glassCard()
                GlassGroup {
                    HStack {
                        GlassChip(title: "通信日志", symbol: "doc.text") { showLog = true }
                        GlassChip(title: "断开连接", symbol: "bolt.slash.fill", selected: true, tint: .red) { ble.disconnect() }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 8)
        }
        .onChange(of: pickedPhoto) { item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await MainActor.run { appearance.setPhoto(data: data) }
                }
                await MainActor.run { pickedPhoto = nil }
            }
        }
        .sheet(isPresented: $showLog) {
            NavigationStack {
                List(Array(ble.log.reversed().enumerated()), id: \.offset) {
                    Text($0.element).font(.system(.caption, design: .monospaced))
                }
                .navigationTitle("日志").navigationBarTitleDisplayMode(.inline)
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
                            if st == .photo && appearance.photo == nil { return }   // 先选照片
                            appearance.settings.style = st
                        }
                    }
                }
            }
            switch appearance.settings.style {
            case .aurora:
                Text("极光背景会随工作模式变色。").font(.caption).foregroundStyle(.white.opacity(0.6))
            case .solid:
                ColorPicker("背景颜色", selection: rgbBinding($appearance.settings.color1), supportsOpacity: false)
            case .gradient:
                ColorPicker("起始颜色", selection: rgbBinding($appearance.settings.color1), supportsOpacity: false)
                ColorPicker("结束颜色", selection: rgbBinding($appearance.settings.color2), supportsOpacity: false)
            case .photo:
                HStack { Image(systemName: "drop"); Slider(value: $appearance.settings.blur, in: 0...30) }
            }
            if appearance.settings.style != .aurora {
                HStack { Image(systemName: "moon.fill"); Slider(value: $appearance.settings.dim, in: 0...0.7) }
            }
            HStack {
                PhotosPicker(selection: $pickedPhoto, matching: .images) {
                    Label(appearance.photo == nil ? "选择照片" : "更换照片", systemImage: "photo.on.rectangle")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                }
                .glass(Capsule(), interactive: true)
                if appearance.photo != nil {
                    GlassChip(title: "删除照片", symbol: "trash") { appearance.removePhoto() }
                }
            }
        }
        .foregroundStyle(.white).glassCard()
    }
}
