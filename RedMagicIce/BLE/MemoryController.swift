import Foundation
import Combine

enum StoredMode: Codable, Equatable {
    case manual(level: Int), smart, boost

    var title: String {
        switch self {
        case .manual(let l): return "手動 \(l + 1) 檔"
        case .smart: return "智慧溫控"
        case .boost: return "破壞神"
        }
    }
}

/// 記憶上次狀態:工作模式(手動檔位 / 智慧溫控 / 破壞神)與燈效。
/// - 在 App 內按電源開機時,自動恢復上次模式(與原版「記住上次軟體模式」一致)。
/// - 連線後若散熱器正在運轉但沒有任何模式,可自動恢復模式與燈效;絕不會自動替你開機。
final class MemoryController: ObservableObject {
    @Published var enabled: Bool { didSet { UserDefaults.standard.set(enabled, forKey: Self.enabledKey) } }
    @Published var autoRestore: Bool { didSet { UserDefaults.standard.set(autoRestore, forKey: Self.autoKey) } }
    @Published private(set) var lastMode: StoredMode?

    private static let enabledKey = "memory.enabled"
    private static let autoKey = "memory.autoRestore"
    private static let modeKey = "memory.lastMode.v1"

    private weak var ble: CoolerBLEManager?
    private weak var light: LightController?
    private var bag = Set<AnyCancellable>()

    init() {
        let d = UserDefaults.standard
        enabled = d.object(forKey: Self.enabledKey) as? Bool ?? true
        autoRestore = d.object(forKey: Self.autoKey) as? Bool ?? true
        if let data = d.data(forKey: Self.modeKey) { lastMode = try? JSONDecoder().decode(StoredMode.self, from: data) }
    }

    func attach(_ ble: CoolerBLEManager, _ light: LightController) {
        guard self.ble == nil else { return }
        self.ble = ble
        self.light = light

        ble.onUserPowerOn = { [weak self] in self?.restoreMode() }

        ble.$mode.removeDuplicates().sink { [weak self] m in self?.record(m) }.store(in: &bag)

        ble.$connected.removeDuplicates().filter { $0 }.sink { [weak self] _ in
            // 等初始狀態讀回(模式旗標、運轉狀態)後再判斷
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { self?.restoreOnConnect() }
        }.store(in: &bag)
    }

    // MARK: 記錄
    private func record(_ m: CoolerWorkMode) {
        guard enabled, let ble, ble.connected else { return }
        let stored: StoredMode
        switch m {
        case .manual(let l): stored = .manual(level: l)
        case .smart: stored = .smart
        case .boost: stored = .boost
        case .idle: return          // 關機/待機不覆蓋記憶
        }
        guard stored != lastMode else { return }
        lastMode = stored
        if let d = try? JSONEncoder().encode(stored) { UserDefaults.standard.set(d, forKey: Self.modeKey) }
    }

    // MARK: 恢復
    /// 在 App 內開機後呼叫
    func restoreMode() {
        guard enabled, let ble, let m = lastMode else { return }
        apply(m, on: ble)
    }

    func restoreAll() {
        restoreMode()
        light?.restoreActive()
    }

    func forget() {
        lastMode = nil
        UserDefaults.standard.removeObject(forKey: Self.modeKey)
    }

    private func restoreOnConnect() {
        guard enabled, autoRestore, let ble, ble.connected else { return }
        // 只在散熱器已在運轉、且硬體沒有任何模式旗標時補上模式;不會替使用者開機
        if ble.running, ble.mode == .idle, let m = lastMode { apply(m, on: ble) }
        light?.restoreActive()
    }

    private func apply(_ m: StoredMode, on ble: CoolerBLEManager) {
        switch m {
        case .manual(let l): ble.setManual(level: l)
        case .smart: ble.setSmart(true)
        case .boost: ble.setBoost(true)
        }
    }
}
