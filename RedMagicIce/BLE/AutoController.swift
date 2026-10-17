import Foundation
import Combine

enum AutoKind: String, Codable, CaseIterable, Identifiable {
    case free, battery, target
    var id: String { rawValue }
    var title: String {
        switch self {
        case .free: return "自由變頻"
        case .battery: return "電池溫控"
        case .target: return "目標溫度"
        }
    }
    var symbol: String {
        switch self {
        case .free: return "waveform.path.ecg"
        case .battery: return "battery.75percent"
        case .target: return "scope"
        }
    }
}

enum BatterySource: String, Codable, CaseIterable, Identifiable {
    case thermalState, simulated
    var id: String { rawValue }
    var title: String { self == .thermalState ? "系統熱狀態" : "手動模擬" }
}

struct AutoSettings: Codable, Equatable {
    var freeCurve = TempCurve.freeDefault        // 舊版存檔的自由變頻曲線(現為第 1 組預設的來源)
    var batteryCurve = TempCurve.batteryDefault
    var targetTemp = 18.0
    var batterySource = BatterySource.thermalState
    var simulatedBattery = 36.0
    var interval = 6.0          // 評估間隔(秒),原版 6 秒

    // 以下用 Optional,讓舊版存檔仍可解碼
    var freePresets: [TempCurve]?
    var activeFreePreset: Int?
    var autoBoost: Bool?

    var presetList: [TempCurve] {
        get { freePresets ?? [freeCurve, TempCurve.presetLowTemp, TempCurve.presetDaily] }
        set { freePresets = newValue }
    }
    var activePreset: Int {
        get { min(max(activeFreePreset ?? 0, 0), 2) }
        set { activeFreePreset = newValue }
    }
    var activeFreeCurve: TempCurve {
        get { presetList[activePreset] }
        set { var l = presetList; l[activePreset] = newValue; presetList = l }
    }
    var allowAutoBoost: Bool {
        get { autoBoost ?? false }
        set { autoBoost = newValue }
    }
}

/// 三種自動溫控:自由變頻(依散熱器溫度曲線)、電池溫控(依手機溫度曲線)、目標溫度(維持散熱器目標溫度)。
/// 軟體定時量測 → 算出檔位 → 只在檔位變化時寫入 1012。可選「必要時自動啟用破壞神」(第 11 檔)。
final class AutoController: ObservableObject {
    @Published private(set) var active: AutoKind?
    @Published private(set) var status = ""
    @Published private(set) var currentLevel: Int?          // index 0...10(10 = 破壞神)
    @Published var settings: AutoSettings { didSet { save() } }

    private weak var ble: CoolerBLEManager?
    private var timer: Timer?
    private var bag = Set<AnyCancellable>()
    private var lastEval = Date.distantPast
    private var startedAt = Date()
    private var stabilizer = ThermalStabilizer()
    private var gate = AutoBoostGate()
    private var autoBoostActive = false
    private static let key = "autoSettings.v1"

    init() {
        if let d = UserDefaults.standard.data(forKey: Self.key),
           let s = try? JSONDecoder().decode(AutoSettings.self, from: d) { settings = s } else { settings = AutoSettings() }
    }

    func attach(_ ble: CoolerBLEManager) {
        guard self.ble == nil else { return }
        self.ble = ble
        ble.onUserControl = { [weak self] in self?.stop(releaseBoost: false) }     // 使用者手動切換任何模式 → 結束自動
        // 藍牙在背景推送溫度時也能評估(定時器在背景會被暫停)
        ble.$temperatureC.sink { [weak self] t in self?.evaluateIfDue(cooler: t) }.store(in: &bag)
        ble.$connected.removeDuplicates().sink { [weak self] on in if !on { self?.stop(releaseBoost: false) } }.store(in: &bag)
    }

    /// 目前用於電池溫控的手機溫度
    func batteryTemp() -> Double {
        switch settings.batterySource {
        case .simulated: return settings.simulatedBattery
        case .thermalState: return AutoLogic.estimatedTemp(ProcessInfo.processInfo.thermalState)
        }
    }

    func start(_ kind: AutoKind) {
        guard let ble, ble.connected else { return }
        timer?.invalidate()
        stabilizer.reset(); gate.reset()
        autoBoostActive = false
        startedAt = Date()
        currentLevel = nil
        ble.autoModeTitle = kind.title
        active = kind
        let first = compute(kind, cooler: ble.temperatureC)
        let level = first?.level ?? 4                               // 沒讀到溫度先用第 4 檔
        ble.setManual(level: min(level, 10) - 1, fromAuto: true)    // 前置:智慧/破壞神 OFF + 開機 + 先給檔位
        currentLevel = min(level, 10) - 1
        if level == 11 { applyLevel(11) }
        lastEval = Date()
        status = first?.text ?? "等待溫度資料…"
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.evaluateIfDue(cooler: self.ble?.temperatureC)
        }
    }

    func stop(releaseBoost: Bool = true) {
        guard active != nil else { return }
        timer?.invalidate(); timer = nil
        active = nil
        currentLevel = nil
        status = ""
        if autoBoostActive, releaseBoost { ble?.setBoost(false, fromAuto: true) }
        autoBoostActive = false
        ble?.autoModeTitle = nil
    }

    /// 計算目前應輸出的檔位(1...10,或 11 = 破壞神)
    private func compute(_ kind: AutoKind, cooler: Float?) -> (level: Int, text: String)? {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let boostOK = settings.allowAutoBoost
        let currentIdx = currentLevel.map { min($0, 9) }
        switch kind {
        case .free, .battery:
            let temp: Double
            let curve: TempCurve
            let label: String
            if kind == .free {
                guard let t = cooler else { return nil }
                temp = Double(t); curve = settings.activeFreeCurve; label = String(format: "散熱器 %.1f°C", t)
            } else {
                temp = batteryTemp(); curve = settings.batteryCurve; label = String(format: "手機約 %.0f°C", temp)
            }
            let raw = Float(curve.level(at: temp))
            // 未超過 10 檔時沿用 0.55 遲滯;超過 10.65 才交給破壞神閘門
            let requested: Float = (boostOK && raw >= AutoBoostGate.enterLevel)
                ? raw : Float(AutoLogic.curveIndex(curve: curve, temp: temp, current: currentIdx) + 1)
            let level = gate.resolve(requested: requested, boostEnabled: boostOK, urgent: false, nowMs: nowMs)
            return (level, "\(label) → \(level == 11 ? "破壞神" : "\(level) 檔")")
        case .target:
            guard let t = cooler else { return nil }
            let s = stabilizer.decideCoolerTarget(measured: t, target: Float(settings.targetTemp),
                                                  maxLogicalLevel: boostOK ? 11 : 10, nowMs: nowMs)
            let level = gate.resolve(requested: Float(s.level), boostEnabled: boostOK,
                                     urgent: s.reason == "urgent-up", nowMs: nowMs)
            return (level, String(format: "散熱器 %.1f°C / 目標 %.1f°C → %@(%@)", s.filtered, settings.targetTemp,
                                  level == 11 ? "破壞神" : "\(level) 檔", s.reason))
        }
    }

    private func applyLevel(_ level: Int) {
        guard let ble else { return }
        if level == 11 {
            if !autoBoostActive { autoBoostActive = true; ble.setBoost(true, fromAuto: true) }
        } else {
            if autoBoostActive { autoBoostActive = false; ble.setBoost(false, fromAuto: true) }
            ble.setFanLevel(level - 1)
        }
        currentLevel = level - 1
    }

    private func evaluateIfDue(cooler: Float?) {
        guard let kind = active, let ble, ble.connected else { return }
        let interval = kind == .target ? min(settings.interval, 3) : settings.interval
        guard Date().timeIntervalSince(lastEval) >= max(interval, 2) else { return }
        // 外部(實體按鍵)切到智慧溫控/破壞神,或散熱器已關閉 → 結束,不會自動開機
        switch ble.mode {
        case .smart: stop(releaseBoost: false); return
        case .boost: if !autoBoostActive { stop(releaseBoost: false); return }
        default: break
        }
        if !ble.running && Date().timeIntervalSince(startedAt) > 12 { stop(releaseBoost: false); return }
        guard let d = compute(kind, cooler: cooler) else { status = "沒有讀到散熱器溫度,暫不調整"; return }
        lastEval = Date()
        status = d.text
        if d.level - 1 != currentLevel { applyLevel(d.level) }
    }

    private func save() {
        if let d = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(d, forKey: Self.key) }
    }
}
