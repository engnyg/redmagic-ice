import Foundation

/// 实验功能:探测 1012(风扇档位特征)能否接受高于原版上限(80)的值。
/// 原版 App 从不写入超过 80;固件可能忽略、限幅、报错或触发保护,这里只做记录。
@MainActor
final class OverclockLab: ObservableObject {
    struct Sample: Identifiable {
        let id = UUID()
        let value: Int
        let rpm: Int?
        let powerW: Int?
        let readback: Int?
        let note: String
    }

    static let stockMax = Int(CoolerProtocol.fanLevelValues.last ?? 80)

    @Published var value = OverclockLab.stockMax
    @Published var withBoost = false
    @Published var samples: [Sample] = []
    @Published var sweeping = false
    @Published var status = ""

    private weak var ble: CoolerBLEManager?
    private var sweepTask: Task<Void, Never>?

    func attach(_ ble: CoolerBLEManager) { self.ble = ble }

    /// 写入一个值,等待 5 秒让转速稳定后记录一条样本。
    func apply(_ v: Int) {
        let v = min(max(v, 0), 255)
        value = v
        ble?.lastWriteError = nil
        ble?.setFanRaw(UInt8(v), boost: withBoost)
        status = "已写入 \(v),等待转速稳定…"
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard let self, !self.sweeping else { return }
            self.record(v)
            self.status = "已记录 \(v)"
        }
    }

    func restore() {
        stopSweep()
        value = Self.stockMax
        withBoost = false
        ble?.setManual(level: CoolerProtocol.fanLevelValues.count - 1)
        status = "已恢复到第 10 档(\(Self.stockMax))"
    }

    func startSweep() {
        guard !sweeping, let ble else { return }
        sweeping = true
        samples.removeAll()
        sweepTask = Task { [weak self] in
            guard let self else { return }
            var v = Self.stockMax
            var prevRpm = 0, flat = 0, bestRpm = 0
            var reason = "已到 255"
            while self.sweeping && v <= 255 {
                ble.lastWriteError = nil
                ble.setFanRaw(UInt8(v), boost: self.withBoost)
                self.value = v
                self.status = "探测 \(v)…"
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if Task.isCancelled || !self.sweeping { reason = "已手动停止"; break }
                if !ble.connected { reason = "连接断开"; break }
                self.record(v)
                if let e = ble.lastWriteError { reason = "写入报错:\(e)"; break }
                let rpm = ble.rpm ?? 0
                bestRpm = max(bestRpm, rpm)
                if v > Self.stockMax {
                    flat = rpm <= prevRpm + max(20, prevRpm / 50) ? flat + 1 : 0
                    if flat >= 2 { reason = "转速不再上升(疑似固件限幅)"; break }
                }
                prevRpm = rpm
                v += (v == Self.stockMax) ? 2 : 4
            }
            self.sweeping = false
            self.restore()
            self.status = "探测结束:\(reason)。最高转速 \(bestRpm) RPM,已恢复第 10 档。"
        }
    }

    func stopSweep() {
        sweeping = false
        sweepTask?.cancel()
    }

    private func record(_ v: Int) {
        guard let ble else { return }
        let note = ble.fanReadback.map { $0 == v ? "读回一致" : "读回 \($0)(被修改)" } ?? "无读回"
        samples.append(Sample(value: v, rpm: ble.rpm, powerW: ble.powerW, readback: ble.fanReadback, note: note))
    }
}
