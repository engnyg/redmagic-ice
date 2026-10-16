import Foundation
import Combine
import ActivityKit

/// 動態島 / 鎖屏即時動態:連線後自動開啟,隨溫度、轉速、功率、模式更新,斷開後結束。
/// BLE 已宣告 bluetooth-central 背景模式,App 退到背景仍可收到通知並更新。
final class LiveActivityController: ObservableObject {
    @Published var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: Self.key)
            if enabled { sync() } else { end() }
        }
    }
    @Published private(set) var systemAllowed = true

    private static let key = "liveActivityEnabled"
    private weak var ble: CoolerBLEManager?
    private var activity: Activity<CoolerActivityAttributes>?
    private var lastState: CoolerActivityAttributes.ContentState?
    private var bag = Set<AnyCancellable>()

    init() {
        enabled = UserDefaults.standard.object(forKey: Self.key) as? Bool ?? true
    }

    func attach(_ ble: CoolerBLEManager) {
        guard self.ble == nil else { return }
        self.ble = ble
        activity = Activity<CoolerActivityAttributes>.activities.first   // App 重啟後接管舊活動
        ble.objectWillChange
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.sync() }
            .store(in: &bag)
    }

    private func currentState(_ ble: CoolerBLEManager) -> CoolerActivityAttributes.ContentState {
        var mode = "off", level: Int?
        if ble.running {
            switch ble.mode {
            case .manual(let l): mode = ble.autoModeTitle == nil ? "manual" : "auto"; level = l
            case .smart: mode = "smart"
            case .boost: mode = "boost"
            case .idle: mode = "idle"
            }
        }
        return .init(temperatureC: ble.temperatureC.map { Int($0.rounded()) }, rpm: ble.rpm, powerW: ble.powerW,
                     running: ble.running, mode: mode, level: level, autoName: ble.autoModeTitle)
    }

    func sync() {
        guard let ble else { return }
        systemAllowed = ActivityAuthorizationInfo().areActivitiesEnabled
        guard enabled, ble.connected else { if !ble.connected { end() }; return }
        let state = currentState(ble)
        if let activity {
            guard state != lastState else { return }
            lastState = state
            Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
        } else if systemAllowed {
            do {
                activity = try Activity.request(
                    attributes: CoolerActivityAttributes(deviceName: ble.deviceName),
                    content: ActivityContent(state: state, staleDate: nil), pushType: nil)
                lastState = state
            } catch {
                ble.noteLog("動態島啟動失敗: \(error.localizedDescription)")
            }
        }
    }

    func end() {
        guard let a = activity else { return }
        activity = nil; lastState = nil
        Task { await a.end(nil, dismissalPolicy: .immediate) }
    }
}
