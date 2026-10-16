import SwiftUI

struct RootView: View {
    @EnvironmentObject var ble: CoolerBLEManager
    var body: some View {
        NavigationView {
            Group {
                if ble.connected { ControlView() } else { ScanView() }
            }
            .navigationTitle("冰环")
            .toolbar {
                if ble.connected {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("断开") { ble.disconnect() }
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

struct ScanView: View {
    @EnvironmentObject var ble: CoolerBLEManager
    var body: some View {
        List {
            Section {
                if ble.state != .poweredOn {
                    Text("请在系统设置中开启蓝牙并允许本 App 使用蓝牙").foregroundColor(.secondary)
                }
                Button(ble.scanning ? "扫描中…" : "扫描散热器") { ble.startScan() }
                    .disabled(ble.state != .poweredOn || ble.scanning)
            }
            Section("发现的设备") {
                ForEach(ble.discovered) { d in
                    Button { ble.connect(d) } label: {
                        HStack { Text(d.name); Spacer(); Text("\(d.rssi) dBm").foregroundColor(.secondary) }
                    }
                }
            }
        }
    }
}

struct ControlView: View {
    @EnvironmentObject var ble: CoolerBLEManager
    @State private var level: Double = 0
    @State private var showLog = false

    private var smartOn: Bool { if case .smart = ble.mode { return true }; return false }
    private var boostOn: Bool { if case .boost = ble.mode { return true }; return false }

    var body: some View {
        Form {
            Section("状态 · \(ble.deviceName)") {
                row("散热器温度", ble.temperatureC.map { String(format: "%.0f °C", $0) })
                row("转速", ble.rpm.map { "\($0) RPM" })
                row("功率", ble.powerW.map { "\($0) W" })
                if !ble.firmware.isEmpty { row("固件", ble.firmware) }
            }
            Section("散热") {
                Toggle("散热开关", isOn: Binding(get: { ble.running }, set: { ble.setPower($0) }))
                Toggle("智能温控", isOn: Binding(get: { smartOn }, set: { ble.setSmart($0) }))
                Toggle("破坏神", isOn: Binding(get: { boostOn }, set: { ble.setBoost($0) }))
            }
            Section("手动档位:\(Int(level) + 1) / \(CoolerProtocol.fanLevelValues.count)") {
                Slider(value: $level, in: 0...Double(CoolerProtocol.fanLevelValues.count - 1), step: 1) { editing in
                    if !editing { ble.setManual(level: Int(level)) }
                }
            }
            Section("灯光") {
                HStack {
                    Button("炫彩") { ble.setLight(.colorful) }
                    Button("呼吸") { ble.setLight(.breathFull) }
                    Button("电池温度") { ble.setLight(.batteryTemp) }
                    Button("关灯") { ble.setLight(.off) }
                }.buttonStyle(.bordered)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                    ForEach(CoolerProtocol.lightPresets) { p in
                        Circle().fill(Color(red: Double(p.r) / 255, green: Double(p.g) / 255, blue: Double(p.b) / 255))
                            .frame(height: 36)
                            .overlay(Circle().stroke(Color.gray.opacity(0.4)))
                            .onTapGesture { ble.setLight(.solid(rgb: (p.r, p.g, p.b))) }
                            .onLongPressGesture { ble.setLight(.breathMono(rgb: (p.r, p.g, p.b))) }
                            .accessibilityLabel(p.name)
                    }
                }
                Text("点按=常亮,长按=单色呼吸").font(.footnote).foregroundColor(.secondary)
            }
            Section { Button("通信日志") { showLog = true } }
        }
        .sheet(isPresented: $showLog) {
            NavigationView {
                List(Array(ble.log.reversed().enumerated()), id: \.offset) { Text($0.element).font(.system(.caption, design: .monospaced)) }
                    .navigationTitle("日志")
            }
        }
    }

    private func row(_ k: String, _ v: String?) -> some View {
        HStack { Text(k); Spacer(); Text(v ?? "--").foregroundColor(.secondary) }
    }
}
