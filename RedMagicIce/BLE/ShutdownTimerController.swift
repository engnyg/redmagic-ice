import Foundation
import Combine
import UserNotifications

/// 定時關機(冰環 2.10.9:1~1440 分鐘)。
/// iOS 無法像 Android 那樣用鬧鐘在背景喚醒 App,因此:
/// - App 在前台,或藍牙背景仍有資料進來時,時間一到就關閉散熱器;
/// - 同時排一則本機通知提醒;之後只要重新打開 App 並連線,逾時 10 分鐘內會自動補關。
final class ShutdownTimerController: ObservableObject {
    @Published private(set) var deadline: Date?
    @Published var lastMinutes: Int { didSet { UserDefaults.standard.set(lastMinutes, forKey: Self.minutesKey) } }
    @Published private(set) var message = ""

    private static let deadlineKey = "shutdown.deadline"
    private static let minutesKey = "shutdown.minutes"
    private static let notifID = "shutdown-timer"
    private static let graceSeconds: TimeInterval = 600

    private weak var ble: CoolerBLEManager?
    private var timer: Timer?
    private var bag = Set<AnyCancellable>()

    init() {
        let d = UserDefaults.standard
        let t = d.double(forKey: Self.deadlineKey)
        deadline = t > 0 ? Date(timeIntervalSince1970: t) : nil
        let saved = d.integer(forKey: Self.minutesKey)
        lastMinutes = saved > 0 ? saved : 30
    }

    func attach(_ ble: CoolerBLEManager) {
        guard self.ble == nil else { return }
        self.ble = ble
        ble.$temperatureC.sink { [weak self] _ in self?.checkDue() }.store(in: &bag)
        ble.$connected.removeDuplicates().filter { $0 }.sink { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self?.checkDue() }   // 等狀態讀回再判斷
        }.store(in: &bag)
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.checkDue() }
    }

    func schedule(minutes: Int) {
        let m = min(max(minutes, 1), 1440)
        lastMinutes = m
        let d = Date().addingTimeInterval(TimeInterval(m * 60))
        deadline = d
        message = ""
        UserDefaults.standard.set(d.timeIntervalSince1970, forKey: Self.deadlineKey)
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let c = UNMutableNotificationContent()
            c.title = "極凍・定時關機"
            c.body = "時間到。若散熱器仍在運轉,請開啟極凍,會自動關閉。"
            c.sound = .default
            let req = UNNotificationRequest(identifier: Self.notifID, content: c,
                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(m * 60), repeats: false))
            center.add(req)
        }
    }

    func cancel() { clear(); message = "已取消定時關機" }

    private func clear() {
        deadline = nil
        UserDefaults.standard.removeObject(forKey: Self.deadlineKey)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.notifID])
    }

    private func checkDue() {
        guard let d = deadline, Date() >= d, let ble else { return }
        if Date().timeIntervalSince(d) > Self.graceSeconds {          // 逾時太久就不補關,避免重新連線時突然關機
            clear(); message = "定時關機已逾時,未執行"; return
        }
        guard ble.connected else { return }                          // 等連線
        if ble.running { ble.setPower(false) }
        clear()
        message = "定時關機已執行"
    }
}
