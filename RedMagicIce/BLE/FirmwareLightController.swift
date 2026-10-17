import Foundation
import Combine

/// 固件擴充燈光:逐顆燈珠(16 顆獨立 RGB)與內建 8 種新燈效。
/// 僅限紅魔 8 Pro 且主控固件 8.5.2 / 8.5.3;需散熱器真實運轉才會下發(與原版相同)。
final class FirmwareLightController: ObservableObject {
    enum Kind: Equatable { case pixels, effect(Int) }

    struct Stored: Codable, Equatable {
        var pixels: [RGB] = FirmwareLightController.rainbowRing()
        var pixelBrightness = 60          // 5...100
        var effect = 6
        var palette: [RGB] = FirmwareLight.effects[5].defaultColors
        var speed = 50                    // 0...100
        var effectBrightness = 60         // 5...100
    }

    @Published var stored: Stored { didSet { save() } }
    @Published var consent: Bool { didSet { UserDefaults.standard.set(consent, forKey: Self.consentKey) } }
    @Published var liveApply = true
    @Published private(set) var active: Kind?
    @Published private(set) var status = ""

    private weak var ble: CoolerBLEManager?
    private var debounce: DispatchWorkItem?
    private static let key = "firmwareLight.v1"
    private static let consentKey = "firmwareLight.consent"

    init() {
        let d = UserDefaults.standard
        if let data = d.data(forKey: Self.key), var s = try? JSONDecoder().decode(Stored.self, from: data) {
            // 存檔若被改壞(顏色數不對、效果編號無效),退回預設,避免畫面用到超出範圍的索引
            if s.pixels.count != FirmwareLight.ledCount { s.pixels = Self.rainbowRing() }
            if !FirmwareLight.effects.contains(where: { $0.id == s.effect }) { s.effect = 6 }
            if s.palette.isEmpty || s.palette.count > 8 { s.palette = FirmwareLight.effects.first { $0.id == s.effect }?.defaultColors ?? Stored().palette }
            stored = s
        } else {
            stored = Stored()
        }
        consent = d.bool(forKey: Self.consentKey)
    }

    func attach(_ ble: CoolerBLEManager) { self.ble = ble }

    static func rainbowRing() -> [RGB] {
        (0..<FirmwareLight.ledCount).map { RGB.hsv(Double($0) * 360 / Double(FirmwareLight.ledCount), 1, 1) }
    }

    var capable: Bool { ble?.supportsFirmwareLight ?? false }

    /// 傳送前的共同檢查;通過回傳 true
    private func gate() -> Bool {
        guard consent else { status = "請先閱讀並同意風險說明"; return false }
        guard let ble, ble.connected else { status = "未連線散熱器"; return false }
        guard ble.supportsFirmwareLight else { status = "需要紅魔 8 Pro 並刷入 8.5.2 / 8.5.3 固件"; return false }
        guard ble.running else { status = "散熱器需開機運轉才會生效(已保存設定)"; return false }
        return true
    }

    // MARK: 逐顆燈珠
    func applyPixels() {
        guard gate(), let ble else { return }
        let b = min(max(stored.pixelBrightness, 5), 100)
        ble.replaceLightBatch(FirmwareLight.pixelFrame(colors: stored.pixels, brightness: b))
        active = .pixels
        status = "已送出整圈 \(FirmwareLight.ledCount) 顆燈珠"
    }

    /// 拖動調色時使用:延遲 0.8 秒、只送最後一次
    func schedulePixels() {
        guard liveApply else { return }
        debounce?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.applyPixels() }
        debounce = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: w)
    }

    func setAllPixels(_ c: RGB) { stored.pixels = Array(repeating: c, count: FirmwareLight.ledCount) }
    func setRainbow() { stored.pixels = Self.rainbowRing() }
    func setHalves(_ a: RGB, _ b: RGB) {
        stored.pixels = (0..<FirmwareLight.ledCount).map { $0 < FirmwareLight.ledCount / 2 ? a : b }
    }

    // MARK: 內建燈效
    func chooseEffect(_ id: Int) {
        stored.effect = id
        if let e = FirmwareLight.effects.first(where: { $0.id == id }) { stored.palette = e.defaultColors }
    }

    func startEffect() {
        guard gate(), let ble else { return }
        let b = min(max(stored.effectBrightness, 5), 100)
        guard let packets = FirmwareLight.configuration(effect: stored.effect, colors: stored.palette, speed: stored.speed, brightness: b) else {
            status = "調色盤顏色數不正確"; return
        }
        ble.replaceLightBatch(packets)
        active = .effect(stored.effect)
        status = "已啟動內建燈效:\(FirmwareLight.effects.first { $0.id == stored.effect }?.name ?? "")"
    }

    func stopFirmwareLight() {
        guard let ble else { return }
        ble.sendFirmwareStopIfNeeded()
        active = nil
        status = "已停止固件燈效,請選擇一般燈效"
    }

    private func save() {
        if let d = try? JSONEncoder().encode(stored) { UserDefaults.standard.set(d, forKey: Self.key) }
    }
}
