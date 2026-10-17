import Foundation
import CoreBluetooth

enum CoolerWorkMode: Equatable { case idle, manual(level: Int), smart, boost }

struct DiscoveredCooler: Identifiable {
    let peripheral: CBPeripheral
    var name: String
    var rssi: Int
    var id: UUID { peripheral.identifier }
}

/// CoreBluetooth 封裝:掃描、連線、序列寫入佇列、訂閱通知。
final class CoolerBLEManager: NSObject, ObservableObject {
    @Published var state: CBManagerState = .unknown
    @Published var discovered: [DiscoveredCooler] = []
    @Published var connected = false
    @Published var autoModeTitle: String?    // 自動溫控進行中(自由變頻 / 電池溫控 / 目標溫度)
    @Published var offlinePreview = false   // 未連線時先瀏覽介面(不會傳送指令)
    @Published var scanning = false
    @Published var deviceName = ""
    @Published var temperatureC: Float?
    @Published var rpm: Int?
    @Published var powerW: Int?
    @Published var running = false
    @Published var mode: CoolerWorkMode = .idle
    @Published var firmware = ""
    @Published var mainFirmware = ""      // 2A28 主控固件(例:V8.5.2),擴充燈光需要
    @Published var moduleFirmware = ""    // 2A26 模組固件
    @Published private(set) var queueDepth = 0
    @Published private(set) var otaActive = false        // 刷寫期間凍結所有其他藍牙操作
    @Published private(set) var otaAvailable = false     // 已找到 Telink OTA 特徵
    private var otaChar: CBCharacteristic?
    static let otaCharUUID = CBUUID(string: TelinkOTA.characteristicUUID)
    var onOTANotify: ((Data) -> Void)?
    var onOTAReady: (() -> Void)?
    var onOTANotifyState: ((Error?) -> Void)?
    var onOTADisconnect: (() -> Void)?
    var firmwareLightActive = false         // 固件內建燈效 / 逐顆燈珠生效中(一般燈效前要先送 F4 停止)
    @Published var log: [String] = []
    @Published var lastWriteError: String?
    @Published var lightNoResponseSupported = false   // 1013 是否支援免回覆寫入(快速燈效)
    @Published var lastLightRaw: String?   // 1013 讀回/通知(燈光探測用)
    @Published var fanReadback: Int?     // 1012 讀回值(超頻探測用)

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var chars: [CoolerChar: CBCharacteristic] = [:]
    private var queue: [(CoolerChar, Data, String)] = []
    private var writing = false
    private var pollTimer: Timer?
    private let lastKey = "lastPeripheral"
    private let lastNameKey = "lastPeripheralName"
    private var tempResolver = CoolerTempResolver()
    private var lastTempDisagreementLog = Date.distantPast

    /// 5 Pro / 6 Pro 的 1015 溫度不用 −6(與冰環一致);8 Pro 與還認不出機型的一律 −6。
    private var tempOffsetApplies: Bool {
        let m = CoolerModel.detect(name: deviceName)
        return m != .rm5Pro && m != .rm6Pro
    }

    private func refreshTemperature() {
        let now = Date.timeIntervalSinceReferenceDate
        let offset = tempOffsetApplies
        // 8 Pro 以 1015 為主;其他機型以 1014 為主
        let preferStatus = CoolerModel.detect(name: deviceName) != .rm5Pro && CoolerModel.detect(name: deviceName) != .rm6Pro
        if let t = tempResolver.resolve(applyOffset: offset, preferStatus: preferStatus, now: now) { temperatureC = t }
        if let d = tempResolver.disagreement(applyOffset: offset, now: now), abs(d) >= 3,
           Date().timeIntervalSince(lastTempDisagreementLog) > 30 {
            lastTempDisagreementLog = Date()
            addLog(String(format: "溫度兩個來源差 %.0f°C(1014 減 1015 校正後);目前以%@為準", d, preferStatus ? "1015" : "1014"))
        }
    }

    /// 自動重連時系統不一定給得出名稱(刷完韌體後尤其常見),機型判斷會變成「未知」而停用 8 Pro 功能。
    /// 掃描時看到的名稱存起來,系統給不出可辨識的名稱時改用它。
    private func resolvedName(for p: CBPeripheral) -> String {
        if let n = p.name, CoolerModel.detect(name: n) != .unknown { return n }
        if !deviceName.isEmpty, CoolerModel.detect(name: deviceName) != .unknown { return deviceName }
        if let saved = UserDefaults.standard.string(forKey: lastNameKey) { return saved }
        return p.name ?? deviceName
    }

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
        UserDefaults.standard.set(c.name, forKey: lastNameKey)
    }

    func disconnect() { if let p = peripheral { central.cancelPeripheralConnection(p) } }

    /// 使用者手動切換模式 / 關機時的回呼(用來結束自動溫控)
    var onUserControl: (() -> Void)?

    /// 使用者在 App 內開機後的回呼(用來恢復上次模式)
    var onUserPowerOn: (() -> Void)?

    func setPower(_ on: Bool) {
        if !on { onUserControl?() }
        write(.powerMode, on ? CoolerProtocol.powerOn : CoolerProtocol.powerOff, on ? "散熱 ON" : "散熱 OFF")
        if !on { mode = .idle }
        if on {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.onUserPowerOn?() }
        }
    }

    func setManual(level: Int, fromAuto: Bool = false) {
        if !fromAuto { onUserControl?() }
        write(.autoTemp, CoolerProtocol.flag(false), "智慧 OFF")
        write(.boost, CoolerProtocol.flag(false), "破壞神 OFF")
        if !running { write(.powerMode, CoolerProtocol.powerOn, "散熱 ON") }
        write(.fanMode, CoolerProtocol.fanLevel(index: level), "手動 \(level + 1) 檔")
        mode = .manual(level: level)
    }

    func setSmart(_ on: Bool) {
        onUserControl?()
        write(.boost, CoolerProtocol.flag(false), "破壞神 OFF")
        if on && !running { write(.powerMode, CoolerProtocol.powerOn, "散熱 ON") }
        write(.autoTemp, CoolerProtocol.flag(on), on ? "智慧溫控 ON" : "智慧溫控 OFF")
        mode = on ? .smart : .idle
    }

    /// 破壞神(超頻,UUID 1017)。流程與原版 enqueuePureBoostSequence 一致:
    /// 智慧 OFF → 散熱 ON → 最高檔 → 1017=01,並在 1.3s / 2.1s 各確認一次。
    func setBoost(_ on: Bool, fromAuto: Bool = false) {
        if !fromAuto { onUserControl?() }
        write(.autoTemp, CoolerProtocol.flag(false), "智慧 OFF")
        guard on else {
            write(.boost, CoolerProtocol.flag(false), "破壞神 OFF")
            mode = .idle
            return
        }
        write(.powerMode, CoolerProtocol.powerOn, "確認散熱 ON")
        write(.fanMode, CoolerProtocol.fanLevel(index: CoolerProtocol.fanLevelValues.count - 1), "基準最高檔")
        write(.boost, CoolerProtocol.flag(true), "破壞神 ON")
        for (delay, label) in [(1.3, "二次確認"), (2.1, "三次確認")] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, case .boost = self.mode else { return }   // 期間被切換/關閉則不再補發
                self.write(.autoTemp, CoolerProtocol.flag(false), "\(label):智慧 OFF")
                self.write(.powerMode, CoolerProtocol.powerOn, "\(label):散熱 ON")
                self.write(.boost, CoolerProtocol.flag(true), "破壞神\(label)")
            }
        }
        mode = .boost
    }

    /// 自動溫控專用:只寫 1012(模式切換的前置寫入已在 start 時由 setManual 完成)
    func setFanLevel(_ index: Int) {
        write(.fanMode, CoolerProtocol.fanLevel(index: index), "自動 \(index + 1) 檔")
        mode = .manual(level: index)
    }

    /// 實驗:向 1012 寫入任意原始值(原版最高只寫到 80)。
    func setFanRaw(_ value: UInt8, boost: Bool) {
        onUserControl?()
        write(.autoTemp, CoolerProtocol.flag(false), "實驗:智慧 OFF")
        write(.boost, CoolerProtocol.flag(boost), boost ? "實驗:破壞神 ON" : "實驗:破壞神 OFF")
        if !running { write(.powerMode, CoolerProtocol.powerOn, "散熱 ON") }
        write(.fanMode, Data([value]), "實驗:風扇原始值 \(value)")
        mode = boost ? .boost : .manual(level: CoolerProtocol.fanLevelValues.count - 1)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.readValue(.fanMode) }
    }

    // MARK: Telink OTA
    var otaContext: (peripheral: CBPeripheral, characteristic: CBCharacteristic)? {
        guard connected, let p = peripheral, let c = otaChar else { return nil }
        return (p, c)
    }

    /// 開始 / 結束刷寫:開始時清空佇列、停止輪詢與固件燈效狀態,之後只允許 OTA 控制器寫入
    func setOTAActive(_ on: Bool) {
        otaActive = on
        if on {
            pollTimer?.invalidate(); pollTimer = nil
            queue.removeAll(); queueDepth = 0
            writing = false
            firmwareLightActive = false
            addLog("OTA:開始,已凍結其他藍牙操作")
        } else {
            if connected { startPolling() }
            addLog("OTA:結束,已恢復一般操作")
        }
    }

    // MARK: 固件擴充燈光(8 Pro + 8.5.2 / 8.5.3)
    var supportsFirmwareLight: Bool {
        FirmwareLight.isCapable(is8Pro: CoolerModel.detect(name: deviceName) == .rm8Pro, revision: mainFirmware)
    }

    /// 以新的一批燈光封包取代尚未送出的舊批次(避免連續調色時佇列堆積)
    func replaceLightBatch(_ packets: [Data]) {
        guard !otaActive else { return }
        queue.removeAll { $0.2 == "燈光批" }
        for p in packets { queue.append((.light, p, "燈光批")) }
        queueDepth = queue.count
        firmwareLightActive = true
        pump()
    }

    func sendFirmwareStopIfNeeded() { firmwareLightActive = true; sendFirmwareStopIfActive() }

    private func sendFirmwareStopIfActive() {
        guard firmwareLightActive else { return }
        firmwareLightActive = false
        queue.removeAll { $0.2 == "燈光批" }
        queue.append((.light, FirmwareLight.stop, "停止固件燈效"))
        queueDepth = queue.count
        pump()
    }

    /// 實驗:直接寫入任意位元組到指定特徵(with response)。
    func writeRaw(_ c: CoolerChar, _ data: Data, label: String) { write(c, data, label) }

    func readValue(_ c: CoolerChar) {
        if let p = peripheral, let ch = chars[c], ch.properties.contains(.read) { p.readValue(for: ch) }
    }

    func setLight(_ m: LightMode) {
        sendFirmwareStopIfActive()
        write(.light, CoolerProtocol.lightPayload(m), "燈光")
    }

    /// 軟體燈效逐幀傳送:佇列忙就丟幀(與原版一致,風扇/模式命令優先),不寫日誌避免刷屏。
    @discardableResult
    func sendLightFrame(_ rgb: RGB, fast: Bool = false) -> Bool {
        if firmwareLightActive { sendFirmwareStopIfActive(); return false }
        guard !otaActive, connected, let ch = chars[.light], let p = peripheral, !writing, queue.isEmpty else { return false }
        let data = CoolerProtocol.lightPayload(.solid(rgb: rgb.tuple))
        // 快速燈效:特徵支援免回覆寫入時直接送出,不必等設備回覆(仍只在佇列空閒時送,風扇命令優先)
        if fast, ch.properties.contains(.writeWithoutResponse) {
            guard p.canSendWriteWithoutResponse else { return false }
            p.writeValue(data, for: ch, type: .withoutResponse)
            return true
        }
        queue.append((.light, data, "燈光幀"))
        pump()
        return true
    }

    // MARK: 寫佇列(序列,with response)
    private func write(_ c: CoolerChar, _ data: Data, _ label: String) {
        guard !otaActive else { return }
        queue.append((c, data, label))
        queueDepth = queue.count
        pump()
    }

    private func pump() {
        guard !otaActive, !writing, let p = peripheral, !queue.isEmpty else { return }
        let (c, data, label) = queue.removeFirst()
        queueDepth = queue.count
        guard let ch = chars[c] else { addLog("缺少特徵 \(c.rawValue):\(label)"); pump(); return }
        writing = true
        if label != "燈光幀" && label != "燈光批" { addLog("TX \(c.rawValue)=\(data.map { String(format: "%02X", $0) }.joined()) \(label)") }
        p.writeValue(data, for: ch, type: .withResponse)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in // 超時保護
            guard let self, self.writing else { return }
            self.writing = false; self.pump()
        }
    }

    /// 顯示用機型名稱(未能辨識時退回藍牙廣播名)
    var modelTitle: String {
        let m = CoolerModel.detect(name: deviceName)
        return m == .unknown ? (deviceName.isEmpty ? m.displayName : deviceName) : m.displayName
    }

    func noteLog(_ s: String) { addLog(s) }

    private func addLog(_ s: String) { log.append(s); if log.count > 200 { log.removeFirst(log.count - 200) } }

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self, !self.otaActive, let p = self.peripheral, self.connected else { return }
            for c in [CoolerChar.status, .temp, .fanSpeed, .power] { if let ch = self.chars[c] { p.readValue(for: ch) } }
        }
    }
}

extension CoolerBLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        state = c.state
        if c.state == .poweredOn, let s = UserDefaults.standard.string(forKey: lastKey), let id = UUID(uuidString: s),
           let p = c.retrievePeripherals(withIdentifiers: [id]).first, peripheral == nil {
            peripheral = p; p.delegate = self; deviceName = resolvedName(for: p)
            c.connect(p, options: nil)  // 自動重連上次裝置
        }
    }

    func centralManager(_ c: CBCentralManager, willRestoreState dict: [String: Any]) {
        if let p = (dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral])?.first {
            peripheral = p; p.delegate = self; deviceName = resolvedName(for: p)
        }
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? p.name ?? ""
        let svc = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?.map { $0.uuidString.uppercased() } ?? []
        let hit = CoolerProtocol.isLikelyCoolerName(name) || svc.contains { ["4A41", "1011", "1015", "101C", "1019", "101A"].contains($0) }
        guard hit else { return }
        let item = DiscoveredCooler(peripheral: p, name: name.isEmpty ? "未命名散熱器" : name, rssi: RSSI.intValue)
        if let i = discovered.firstIndex(where: { $0.id == item.id }) { discovered[i] = item } else { discovered.append(item) }
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        if CoolerModel.detect(name: deviceName) == .unknown { deviceName = resolvedName(for: p) }
        p.discoverServices(nil)
        // 與 Android 一致:服務發現 7 秒超時則重連
        DispatchQueue.main.asyncAfter(deadline: .now() + 7) { [weak self] in
            guard let self, !self.connected, self.peripheral === p else { return }
            self.addLog("服務發現超時,重連"); c.cancelPeripheralConnection(p); c.connect(p, options: nil)
        }
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        if let e = error as NSError? { addLog("藍牙斷線:\(e.domain) \(e.code) \(e.localizedDescription)") } else { addLog("藍牙斷線(設備或系統主動結束連線)") }
        connected = false; chars.removeAll(); queue.removeAll(); writing = false; pollTimer?.invalidate()
        otaChar = nil; otaAvailable = false
        onOTADisconnect?()
        if peripheral === p, UserDefaults.standard.string(forKey: lastKey) != nil { c.connect(p, options: nil) }
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        addLog("連線失敗 \(error?.localizedDescription ?? "")"); c.connect(p, options: nil)
    }
}

extension CoolerBLEManager: CBPeripheralDelegate {
    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        p.services?.forEach { p.discoverCharacteristics(nil, for: $0) }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        for ch in s.characteristics ?? [] {
            if ch.uuid == Self.otaCharUUID { otaChar = ch; otaAvailable = true; continue }   // 不在連線時訂閱或讀取,刷寫時才使用
            guard let key = CoolerChar(rawValue: ch.uuid.uuidString.uppercased()) else { continue }
            // 101C/101D 為 1019/101A 的備用,優先使用前者(與原版一致)
            switch key {
            case .fanSpeedAlt: chars[.fanSpeed] = ch
            case .powerAlt: chars[.power] = ch
            case .fanSpeed where chars[.fanSpeed] != nil: break
            case .power where chars[.power] != nil: break
            default: chars[key] = ch
            }
            if key == .light { lightNoResponseSupported = ch.properties.contains(.writeWithoutResponse) }
            if ch.properties.contains(.notify) || ch.properties.contains(.indicate) { p.setNotifyValue(true, for: ch) }
            if ch.properties.contains(.read) { p.readValue(for: ch) }
        }
        if chars[.powerMode] != nil, chars[.status] != nil, !connected {
            connected = true
            offlinePreview = false
            addLog("已連線並驗證特徵")
            startPolling()
        }
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        if ch.uuid == Self.otaCharUUID { if let v = ch.value { onOTANotify?(v) }; return }
        guard let v = ch.value, let key = CoolerChar(rawValue: ch.uuid.uuidString.uppercased()) else { return }
        switch key {
        case .status:
            let u = CoolerProtocol.parseStatus(v)
            if let raw = CoolerProtocol.parseStatusTempRaw(v) { tempResolver.note1015(raw: raw, now: Date.timeIntervalSinceReferenceDate); refreshTemperature() }
            if let r = u.rpm { rpm = r }
            if let w = u.powerW { powerW = w }
            if let r = u.running { running = r; if !r { mode = .idle } }
        case .temp: if let t = CoolerProtocol.parseTemp(v) { tempResolver.note1014(t, now: Date.timeIntervalSinceReferenceDate); refreshTemperature() }
        case .fanSpeed, .fanSpeedAlt: if let r = CoolerProtocol.parseRpm(v) { rpm = r }
        case .power, .powerAlt: if let w = CoolerProtocol.parsePower(v) { powerW = w }
        case .powerMode: if let b = v.first { running = (b == 2) ; if b == 3 { mode = .idle } }
        case .fanMode: fanReadback = v.first.map(Int.init)
        case .light: lastLightRaw = v.map { String(format: "%02X", $0) }.joined(separator: " ")
        case .autoTemp: if v.first == 1 { mode = .smart }
        case .boost: if v.first == 1 { mode = .boost }
        case .firmwareModule, .firmwareMain:
            let text = String(data: v, encoding: .utf8) ?? v.map { String(format: "%02X", $0) }.joined()
            firmware = text
            if key == .firmwareMain { mainFirmware = text } else { moduleFirmware = text }
        default: break
        }
    }

    func peripheral(_ p: CBPeripheral, didWriteValueFor ch: CBCharacteristic, error: Error?) {
        if let error { addLog("寫入失敗: \(error.localizedDescription)"); lastWriteError = error.localizedDescription }
        else { lastWriteError = nil }
        writing = false; pump()
    }
}

extension CoolerBLEManager {
    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor ch: CBCharacteristic, error: Error?) {
        if ch.uuid == Self.otaCharUUID { onOTANotifyState?(error) }
    }

    func peripheralIsReady(toSendWriteWithoutResponse p: CBPeripheral) {
        onOTAReady?()
    }
}
