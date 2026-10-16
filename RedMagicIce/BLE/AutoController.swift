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
    var freeCurve = TempCurve.freeDefault
    var batteryCurve = TempCurve.batteryDefault
    var targetTemp = 18.0
    var batterySource = BatterySource.thermalState
    var simulatedBattery = 36.0
    var interval = 6.0          // 評估間隔(秒),原版 6 秒
}

/// 三種自動溫控:自由變頻(依散熱器溫度曲線)、電池溫控(依手機溫度曲線)、目標溫度(維持散熱器目標溫度)。
/// 實作方式與原版相同:軟體定時量測 → 算出檔位 → 只在檔位變化時寫入 1012。
final class AutoController: ObservableObject {
    @Published private(set) var active: AutoKind?
    @Published private(set) var status = ""
    @Published private(set) var currentLevel: Int?
    @Published var settings: AutoSettings { didSet { save() } }

    private weak var ble: CoolerBLEManager?
    private var timer: Timer?
    private var bag = Set<AnyCancellable>()
    private var lastEval = Date.distantPast
    private var startedAt = Date()
    private static let key = "autoSettings.v1"

    init() {
        if let d = UserDefaults.standard.data(forKey: Self.key),
           let s = try? JSONDecoder().decode(AutoSettings.self, from: d) { settings = s } else { settings = AutoSettings() }
    }

    func attach(_ ble: CoolerBLEManager) {
        guard self.ble == nil else { return }
        self.ble = ble
        ble.onUserControl = { [weak self] in self?.stop() }          // 使用者手動切換任何模式 → 結束自動
        // 藍牙在背景推送溫度時也能評估(定時器在背景會被暫停)
        ble.$temperatureC.sink { [weak self] t in self?.evaluateIfDue(cooler: t) }.store(in: &bag)
        ble.$connected.removeDuplicates().sink { [weak self] on in if !on { self?.stop() } }.store(in: &bag)
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
        startedAt = Date()
        currentLevel = nil
        ble.autoModeTitle = kind.title
        active = kind
        let first = decide(kind, cooler: ble.temperatureC)?.index ?? 3     // 沒讀到溫度先用第 4 檔
        currentLevel = first
        lastEval = Date()
        ble.setManual(level: first, fromAuto: true)
        status = decide(kind, cooler: ble.temperatureC)?.text ?? "等待溫度資料…"
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.evaluateIfDue(cooler: self.ble?.temperatureC)
        }
    }

    func stop() {
        guard active != nil else { return }
        timer?.invalidate(); timer = nil
        active = nil
        currentLevel = nil
        status = ""
        ble?.autoModeTitle = nil
    }

    private func decide(_ kind: AutoKind, cooler: Float?) -> (index: Int, text: String)? {
        switch kind {
        case .free:
            guard let t = cooler else { return nil }
            let i = AutoLogic.curveIndex(curve: settings.freeCurve, temp: Double(t), current: currentLevel)
            return (i, String(format: "散熱器 %.1f°C → %d 檔", t, i + 1))
        case .battery:
            let bt = batteryTemp()
            let i = AutoLogic.curveIndex(curve: settings.batteryCurve, temp: bt, current: currentLevel)
            return (i, String(format: "手機約 %.0f°C → %d 檔", bt, i + 1))
        case .target:
            guard let t = cooler else { return nil }
            let i = AutoLogic.targetIndex(cooler: Double(t), target: settings.targetTemp, current: currentLevel)
            return (i, String(format: "散熱器 %.1f°C / 目標 %.1f°C → %d 檔", t, settings.targetTemp, i + 1))
        }
    }

    private func evaluateIfDue(cooler: Float?) {
        guard let kind = active, let ble, ble.connected else { return }
        guard Date().timeIntervalSince(lastEval) >= max(settings.interval, 2) else { return }
        // 外部(實體按鍵)切到智慧/破壞神,或散熱器已關閉 → 結束,不會自動開機
        switch ble.mode {
        case .smart, .boost: stop(); return
        default: break
        }
        if !ble.running && Date().timeIntervalSince(startedAt) > 12 { stop(); return }
        guard let d = decide(kind, cooler: cooler) else { status = "沒有讀到散熱器溫度,暫不調整"; return }
        lastEval = Date()
        status = d.text
        if d.index != currentLevel {
            currentLevel = d.index
            ble.setFanLevel(d.index)
        }
    }

    private func save() {
        if let d = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(d, forKey: Self.key) }
    }
}
