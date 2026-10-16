import Foundation
import CoreBluetooth

enum CoolerWorkMode: Equatable { case idle, manual(level: Int), smart, boost }

struct DiscoveredCooler: Identifiable {
    let peripheral: CBPeripheral
    var name: String
    var rssi: Int
    var id: UUID { peripheral.identifier }
}

/// CoreBluetooth 封装:扫描、连接、串行写入队列、订阅通知。
final class CoolerBLEManager: NSObject, ObservableObject {
    @Published var state: CBManagerState = .unknown
    @Published var discovered: [DiscoveredCooler] = []
    @Published var connected = false
    @Published var scanning = false
    @Published var deviceName = ""
    @Published var temperatureC: Float?
    @Published var rpm: Int?
    @Published var powerW: Int?
    @Published var running = false
    @Published var mode: CoolerWorkMode = .idle
    @Published var firmware = ""
    @Published var log: [String] = []
    @Published var lastWriteError: String?
    @Published var fanReadback: Int?     // 1012 读回值(超频探测用)

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var chars: [CoolerChar: CBCharacteristic] = [:]
    private var queue: [(CoolerChar, Data, String)] = []
    private var writing = false
    private var pollTimer: Timer?
    private let lastKey = "lastPeripheral"

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main,
                                   options: [CBCentralManagerOptionRestoreIdentifierKey: "redmagic.ice.central"])
    }

    // MARK: 公共操作
    func startScan() {
        guard central.state == .poweredOn else { return }
        discovered.removeAll()
        scanning = true
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in self?.stopScan() }
    }

    func stopScan() { central.stopScan(); scanning = false }

    func connect(_ c: DiscoveredCooler) {
        stopScan()
        peripheral = c.peripheral
        deviceName = c.name
        c.peripheral.delegate = self
        central.connect(c.peripheral, options: nil)
        UserDefaults.standard.set(c.peripheral.identifier.uuidString, forKey: lastKey)
    }

    func disconnect() { if let p = peripheral { central.cancelPeripheralConnection(p) } }

    func setPower(_ on: Bool) {
        write(.powerMode, on ? CoolerProtocol.powerOn : CoolerProtocol.powerOff, on ? "散热 ON" : "散热 OFF")
        if !on { mode = .idle }
    }

    func setManual(level: Int) {
        write(.autoTemp, CoolerProtocol.flag(false), "智能 OFF")
        write(.boost, CoolerProtocol.flag(false), "破坏神 OFF")
        if !running { write(.powerMode, CoolerProtocol.powerOn, "散热 ON") }
        write(.fanMode, CoolerProtocol.fanLevel(index: level), "手动 \(level + 1) 档")
        mode = .manual(level: level)
    }

    func setSmart(_ on: Bool) {
        write(.boost, CoolerProtocol.flag(false), "破坏神 OFF")
        if on && !running { write(.powerMode, CoolerProtocol.powerOn, "散热 ON") }
        write(.autoTemp, CoolerProtocol.flag(on), on ? "智能温控 ON" : "智能温控 OFF")
        mode = on ? .smart : .idle
    }

    /// 破坏神(超频,UUID 1017)。流程与原版 enqueuePureBoostSequence 一致:
    /// 智能 OFF → 散热 ON → 最高档 → 1017=01,并在 1.3s / 2.1s 各确认一次。
    func setBoost(_ on: Bool) {
        write(.autoTemp, CoolerProtocol.flag(false), "智能 OFF")
        guard on else {
            write(.boost, CoolerProtocol.flag(false), "破坏神 OFF")
            mode = .idle
            return
        }
        write(.powerMode, CoolerProtocol.powerOn, "确认散热 ON")
        write(.fanMode, CoolerProtocol.fanLevel(index: CoolerProtocol.fanLevelValues.count - 1), "基准最高档")
        write(.boost, CoolerProtocol.flag(true), "破坏神 ON")
        for (delay, label) in [(1.3, "二次确认"), (2.1, "三次确认")] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, case .boost = self.mode else { return }   // 期间被切换/关闭则不再补发
                self.write(.autoTemp, CoolerProtocol.flag(false), "\(label):智能 OFF")
                self.write(.powerMode, CoolerProtocol.powerOn, "\(label):散热 ON")
                self.write(.boost, CoolerProtocol.flag(true), "破坏神\(label)")
            }
        }
        mode = .boost
    }

    /// 实验:向 1012 写入任意原始值(原版最高只写到 80)。
    func setFanRaw(_ value: UInt8, boost: Bool) {
        write(.autoTemp, CoolerProtocol.flag(false), "实验:智能 OFF")
        write(.boost, CoolerProtocol.flag(boost), boost ? "实验:破坏神 ON" : "实验:破坏神 OFF")
        if !running { write(.powerMode, CoolerProtocol.powerOn, "散热 ON") }
        write(.fanMode, Data([value]), "实验:风扇原始值 \(value)")
        mode = boost ? .boost : .manual(level: CoolerProtocol.fanLevelValues.count - 1)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.readValue(.fanMode) }
    }

    func readValue(_ c: CoolerChar) {
        if let p = peripheral, let ch = chars[c], ch.properties.contains(.read) { p.readValue(for: ch) }
    }

    func setLight(_ m: LightMode) { write(.light, CoolerProtocol.lightPayload(m), "灯光") }

    /// 软件灯效逐帧发送:队列忙就丢帧(与原版一致,风扇/模式命令优先),不写日志避免刷屏。
    @discardableResult
    func sendLightFrame(_ rgb: RGB) -> Bool {
        guard connected, chars[.light] != nil, !writing, queue.isEmpty else { return false }
        queue.append((.light, CoolerProtocol.lightPayload(.solid(rgb: rgb.tuple)), "灯光帧"))
        pump()
        return true
    }

    // MARK: 写队列(串行,with response)
    private func write(_ c: CoolerChar, _ data: Data, _ label: String) {
        queue.append((c, data, label))
        pump()
    }

    private func pump() {
        guard !writing, let p = peripheral, !queue.isEmpty else { return }
        let (c, data, label) = queue.removeFirst()
        guard let ch = chars[c] else { addLog("缺少特征 \(c.rawValue):\(label)"); pump(); return }
        writing = true
        if label != "灯光帧" { addLog("TX \(c.rawValue)=\(data.map { String(format: "%02X", $0) }.joined()) \(label)") }
        p.writeValue(data, for: ch, type: .withResponse)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in // 超时保护
            guard let self, self.writing else { return }
            self.writing = false; self.pump()
        }
    }

    func noteLog(_ s: String) { addLog(s) }

    private func addLog(_ s: String) { log.append(s); if log.count > 200 { log.removeFirst(log.count - 200) } }

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self, let p = self.peripheral, self.connected else { return }
            for c in [CoolerChar.status, .temp, .fanSpeed, .power] { if let ch = self.chars[c] { p.readValue(for: ch) } }
        }
    }
}

extension CoolerBLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        state = c.state
        if c.state == .poweredOn, let s = UserDefaults.standard.string(forKey: lastKey), let id = UUID(uuidString: s),
           let p = c.retrievePeripherals(withIdentifiers: [id]).first, peripheral == nil {
            peripheral = p; p.delegate = self; deviceName = p.name ?? deviceName
            c.connect(p, options: nil)  // 自动重连上次设备
        }
    }

    func centralManager(_ c: CBCentralManager, willRestoreState dict: [String: Any]) {
        if let p = (dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral])?.first {
            peripheral = p; p.delegate = self
        }
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? p.name ?? ""
        let svc = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?.map { $0.uuidString.uppercased() } ?? []
        let hit = CoolerProtocol.isLikelyCoolerName(name) || svc.contains { ["1011", "1015", "101C", "1019", "101A"].contains($0) }
        guard hit else { return }
        let item = DiscoveredCooler(peripheral: p, name: name.isEmpty ? "未命名散热器" : name, rssi: RSSI.intValue)
        if let i = discovered.firstIndex(where: { $0.id == item.id }) { discovered[i] = item } else { discovered.append(item) }
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        p.discoverServices(nil)
        // 与 Android 一致:服务发现 7 秒超时则重连
        DispatchQueue.main.asyncAfter(deadline: .now() + 7) { [weak self] in
            guard let self, !self.connected, self.peripheral === p else { return }
            self.addLog("服务发现超时,重连"); c.cancelPeripheralConnection(p); c.connect(p, options: nil)
        }
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        connected = false; chars.removeAll(); queue.removeAll(); writing = false; pollTimer?.invalidate()
        if peripheral === p, UserDefaults.standard.string(forKey: lastKey) != nil { c.connect(p, options: nil) }
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        addLog("连接失败 \(error?.localizedDescription ?? "")"); c.connect(p, options: nil)
    }
}

extension CoolerBLEManager: CBPeripheralDelegate {
    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        p.services?.forEach { p.discoverCharacteristics(nil, for: $0) }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        for ch in s.characteristics ?? [] {
            guard let key = CoolerChar(rawValue: ch.uuid.uuidString.uppercased()) else { continue }
            // 101C/101D 为 1019/101A 的备用,优先使用前者(与原版一致)
            switch key {
            case .fanSpeedAlt: chars[.fanSpeed] = ch
            case .powerAlt: chars[.power] = ch
            case .fanSpeed where chars[.fanSpeed] != nil: break
            case .power where chars[.power] != nil: break
            default: chars[key] = ch
            }
            if ch.properties.contains(.notify) || ch.properties.contains(.indicate) { p.setNotifyValue(true, for: ch) }
            if ch.properties.contains(.read) { p.readValue(for: ch) }
        }
        if chars[.powerMode] != nil, chars[.status] != nil, !connected {
            connected = true
            addLog("已连接并验证特征")
            startPolling()
        }
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        guard let v = ch.value, let key = CoolerChar(rawValue: ch.uuid.uuidString.uppercased()) else { return }
        switch key {
        case .status:
            let u = CoolerProtocol.parseStatus(v)
            if let t = u.temperatureC { temperatureC = t }
            if let r = u.rpm { rpm = r }
            if let w = u.powerW { powerW = w }
            if let r = u.running { running = r; if !r { mode = .idle } }
        case .temp: if let t = CoolerProtocol.parseTemp(v) { temperatureC = t }
        case .fanSpeed, .fanSpeedAlt: if let r = CoolerProtocol.parseRpm(v) { rpm = r }
        case .power, .powerAlt: if let w = CoolerProtocol.parsePower(v) { powerW = w }
        case .powerMode: if let b = v.first { running = (b == 2) ; if b == 3 { mode = .idle } }
        case .fanMode: fanReadback = v.first.map(Int.init)
        case .autoTemp: if v.first == 1 { mode = .smart }
        case .boost: if v.first == 1 { mode = .boost }
        case .firmwareModule, .firmwareMain:
            firmware = String(data: v, encoding: .utf8) ?? v.map { String(format: "%02X", $0) }.joined()
        default: break
        }
    }

    func peripheral(_ p: CBPeripheral, didWriteValueFor ch: CBCharacteristic, error: Error?) {
        if let error { addLog("写入失败: \(error.localizedDescription)"); lastWriteError = error.localizedDescription }
        else { lastWriteError = nil }
        writing = false; pump()
    }
}
