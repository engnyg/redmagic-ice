import Foundation
import CoreBluetooth

/// Telink OTA 刷寫狀態機。流程與冰環 2.10.46 相同:訂閱通知 → 寫 `00 FF` → 逐包無回應寫入 → 結束包 → 等設備通知 `06 FF 00`。
/// 設備在收到合法結束包之前不會切換到新映像,所以傳輸中途失敗或中止時,通常會保留原本的固件。
final class TelinkOTAController: ObservableObject {
    enum Phase: Equatable {
        case idle, preparing, subscribing, sending, verifying
        case done, unconfirmed(String), failed(String)
        var isRunning: Bool {
            switch self { case .preparing, .subscribing, .sending, .verifying: return true; default: return false }
        }
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var progress = 0.0
    @Published private(set) var detail = ""
    @Published private(set) var trace: [String] = []
    @Published var compatibilityPacing: Bool { didSet { UserDefaults.standard.set(compatibilityPacing, forKey: Self.pacingKey) } }

    private weak var ble: CoolerBLEManager?
    private var frames: [Data] = []
    private var frameIndex = 0
    private var waitingReady = false
    private var lastProgress = Date()
    private var endSent = false
    private var watchdog: Timer?
    private var phaseTimeout: DispatchWorkItem?
    private static let pacingKey = "ota.compatPacing"

    init() {
        compatibilityPacing = UserDefaults.standard.object(forKey: Self.pacingKey) as? Bool ?? true   // 預設相容節奏:慢但穩
    }

    func attach(_ ble: CoolerBLEManager) { self.ble = ble }

    // MARK: 開始 / 中止
    func start(image: Data) {
        guard !phase.isRunning, let ble else { return }
        do { try TelinkOTA.validate(image) } catch { fail("檔案驗證失敗:\(error.localizedDescription)"); return }
        guard ble.connected, CoolerModel.detect(name: ble.deviceName) == .rm8Pro else { fail("需要連線紅魔 8 Pro"); return }
        guard let ctx = ble.otaContext else { fail("設備沒有 Telink OTA 特徵,沒有送出任何資料"); return }

        trace.removeAll(); progress = 0; endSent = false; waitingReady = false
        frames = TelinkOTA.frames(for: image)
        frameIndex = 0
        log("開始:\(image.count) 位元組、\(frames.count - 2) 包資料,SHA-256 \(TelinkOTA.sha256Hex(image).prefix(16))…")
        set(.preparing, "凍結其他藍牙操作")
        ble.setOTAActive(true)
        hook(ble)
        armPhaseTimeout(12, "訂閱通知逾時,沒有送出任何資料")

        let props = ctx.characteristic.properties
        guard props.contains(.writeWithoutResponse) else { fail("OTA 特徵不支援無回應寫入,沒有送出任何資料"); return }
        if props.contains(.notify) || props.contains(.indicate) {
            set(.subscribing, "訂閱 OTA 通知")
            ctx.peripheral.setNotifyValue(true, for: ctx.characteristic)
        } else {
            beginSending()
        }
    }

    /// 中止:尚未送出結束包時,設備不會安裝不完整的映像
    func abort() {
        guard phase.isRunning else { return }
        if endSent {
            finish(.unconfirmed("已送出結束包後中止;請重新連線後核對固件版本"))
        } else {
            log("使用者中止(尚未送出結束包)")
            finish(.failed("已中止。結束包尚未送出,設備通常會保留原本的固件"))
        }
    }

    func reset() { if !phase.isRunning { phase = .idle; progress = 0; detail = ""; trace.removeAll() } }

    // MARK: 內部流程
    private func hook(_ ble: CoolerBLEManager) {
        ble.onOTANotifyState = { [weak self] err in
            guard let self, self.phase == .subscribing else { return }
            if let err { self.fail("訂閱 OTA 通知失敗:\(err.localizedDescription)"); return }
            self.log("通知已訂閱")
            self.beginSending()
        }
        ble.onOTANotify = { [weak self] d in self?.receive([UInt8](d)) }
        ble.onOTAReady = { [weak self] in
            guard let self, self.waitingReady else { return }
            self.waitingReady = false
            self.pump()
        }
        ble.onOTADisconnect = { [weak self] in
            guard let self, self.phase.isRunning else { return }
            if self.endSent {
                self.finish(.unconfirmed("連線已中斷:設備可能正在重啟並安裝。請等待重新連線,並核對固件版本"))
            } else {
                self.finish(.failed("連線中斷於 \(Int(self.progress * 100))%;結束包尚未送出,設備通常會保留原本的固件"))
            }
        }
    }

    private func beginSending() {
        cancelPhaseTimeout()
        set(.sending, "傳輸中")
        lastProgress = Date()
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.phase == .sending, !self.endSent else { return }
            if Date().timeIntervalSince(self.lastProgress) > 8 { self.fail("傳輸停滯超過 8 秒,已停止") }
        }
        pump()
    }

    private func pump() {
        guard phase == .sending, let ctx = ble?.otaContext else { return }
        guard frameIndex < frames.count else { return }
        guard ctx.peripheral.canSendWriteWithoutResponse else { waitingReady = true; return }
        ctx.peripheral.writeValue(frames[frameIndex], for: ctx.characteristic, type: .withoutResponse)
        frameIndex += 1
        lastProgress = Date()
        let dataCount = frames.count - 2
        progress = Double(min(max(frameIndex - 1, 0), dataCount)) / Double(max(dataCount, 1))
        detail = "傳輸中 \(Int(progress * 100))%(\(min(max(frameIndex - 1, 0), dataCount))/\(dataCount) 包)"
        if frameIndex == frames.count {
            endSent = true
            log("結束包已送出,等待設備確認")
            set(.verifying, "資料已送完,等待設備驗證與安裝(最長 20 秒)")
            armPhaseTimeout(20, nil, unconfirmed: "已送出全部資料,但沒有收到安裝確認;請重新連線並核對固件版本")
            return
        }
        let delay = compatibilityPacing ? 0.012 : 0
        if delay == 0 { DispatchQueue.main.async { [weak self] in self?.pump() } }
        else { DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.pump() } }
    }

    private func receive(_ b: [UInt8]) {
        guard b.count >= 3, b[0] == 0x06, b[1] == 0xFF else { return }
        log("通知:\(b.map { String(format: "%02X", $0) }.joined(separator: " "))")
        if b[2] != 0 { fail("設備回報 OTA 錯誤碼 \(b[2])"); return }
        if endSent { finish(.done) }
    }

    // MARK: 收尾
    private func set(_ p: Phase, _ text: String) { phase = p; detail = text; log(text) }

    private func fail(_ message: String) { log("失敗:\(message)"); finish(.failed(message)) }

    private func finish(_ final: Phase) {
        watchdog?.invalidate(); watchdog = nil
        cancelPhaseTimeout()
        if let ctx = ble?.otaContext { ctx.peripheral.setNotifyValue(false, for: ctx.characteristic) }
        ble?.onOTANotify = nil; ble?.onOTAReady = nil; ble?.onOTANotifyState = nil; ble?.onOTADisconnect = nil
        ble?.setOTAActive(false)
        frames.removeAll(); waitingReady = false
        phase = final
        switch final {
        case .done: progress = 1; detail = "設備報告校驗成功,正在重啟。請等待重新連線後核對固件版本"
        case .unconfirmed(let m): detail = m
        case .failed(let m): detail = m
        default: break
        }
        log("結束:\(detail)")
    }

    private func armPhaseTimeout(_ seconds: Double, _ failText: String?, unconfirmed: String? = nil) {
        cancelPhaseTimeout()
        let w = DispatchWorkItem { [weak self] in
            guard let self, self.phase.isRunning else { return }
            if let u = unconfirmed { self.finish(.unconfirmed(u)) } else { self.fail(failText ?? "逾時") }
        }
        phaseTimeout = w
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: w)
    }

    private func cancelPhaseTimeout() { phaseTimeout?.cancel(); phaseTimeout = nil }

    private func log(_ s: String) {
        let t = DateFormatter(); t.dateFormat = "HH:mm:ss.SSS"
        trace.append("\(t.string(from: Date())) \(s)")
        if trace.count > 400 { trace.removeFirst(trace.count - 400) }
        ble?.noteLog("OTA:\(s)")
    }
}
