import Foundation
import Combine

enum HardwareLight: String, Codable, CaseIterable, Identifiable {
    case colorful, breathFull, breathMono, solid, off
    var id: String { rawValue }
    var title: String {
        switch self {
        case .colorful: return "炫彩"
        case .breathFull: return "多色呼吸"
        case .breathMono: return "單色呼吸"
        case .solid: return "常亮"
        case .off: return "關燈"
        }
    }
    var symbol: String {
        switch self {
        case .colorful: return "sparkles"
        case .breathFull: return "aqi.medium"
        case .breathMono: return "circle.dotted"
        case .solid: return "lightbulb.fill"
        case .off: return "lightbulb.slash"
        }
    }
    var usesColor: Bool { self == .breathMono || self == .solid }
    func mode(_ c: RGB) -> LightMode {
        switch self {
        case .colorful: return .colorful
        case .breathFull: return .breathFull
        case .breathMono: return .breathMono(rgb: c.tuple)
        case .solid: return .solid(rgb: c.tuple)
        case .off: return .off
        }
    }
}

struct LinkedLight: Codable, Equatable {
    var kind: HardwareLight
    var color: RGB
}

struct LightSettings: Codable, Equatable {
    var speed: Double = 1.0            // 軟體燈效幀間隔(秒),最小 0.6
    var brightness: Double = 1.0       // 軟體亮度(縮放 RGB,硬體無亮度命令)
    var solid = RGB(r: 67, g: 135, b: 232)
    var colors = LightFrames.defaultColors
    var linkManual = LinkedLight(kind: .solid, color: RGB(r: 55, g: 200, b: 187))
    var linkSmart = LinkedLight(kind: .breathMono, color: RGB(r: 71, g: 215, b: 122))
    var linkBoost = LinkedLight(kind: .breathMono, color: RGB(r: 255, g: 0, b: 0))
    var linkOff = LinkedLight(kind: .off, color: .black)
}

/// 燈光控制:硬體模式、App 驅動的軟體燈效、以及溫度/檔位/模式聯動。
final class LightController: ObservableObject {
    enum Active: Equatable {
        case none, hardware(HardwareLight), software(SoftwareEffect), tempLinked, levelLinked, modeLinked

        var storageKey: String {
            switch self {
            case .none: return "none"
            case .hardware(let k): return "hw:\(k.rawValue)"
            case .software(let e): return "sw:\(e.rawValue)"
            case .tempLinked: return "temp"
            case .levelLinked: return "level"
            case .modeLinked: return "mode"
            }
        }
    }

    @Published private(set) var active: Active = .none { didSet { UserDefaults.standard.set(active.storageKey, forKey: Self.activeKey) } }
    @Published var settings: LightSettings { didSet { save() } }

    private weak var ble: CoolerBLEManager?
    private var timer: Timer?
    private var frame = 0
    private var lastSignature = ""
    private var bag = Set<AnyCancellable>()
    private static let key = "lightSettings.v1"
    private static let activeKey = "lightActive.v1"

    init() {
        if let d = UserDefaults.standard.data(forKey: Self.key),
           let s = try? JSONDecoder().decode(LightSettings.self, from: d) {
            settings = s
        } else {
            settings = LightSettings()
        }
    }

    func attach(_ ble: CoolerBLEManager) {
        guard self.ble == nil else { return }
        self.ble = ble
        ble.$connected.removeDuplicates().sink { [weak self] on in
            guard let self else { return }
            self.lastSignature = ""
            if on { self.restartTimer() } else { self.timer?.invalidate(); self.timer = nil }
        }.store(in: &bag)
        Publishers.CombineLatest(ble.$mode, ble.$running).sink { [weak self] mode, running in
            guard let self, self.active == .modeLinked else { return }
            self.applyModeLinked(mode, running)
        }.store(in: &bag)
    }

    /// 恢復上次使用的燈效(硬體模式 / 動態燈效 / 聯動)
    func restoreActive() {
        guard let key = UserDefaults.standard.string(forKey: Self.activeKey) else { return }
        switch key {
        case "temp": startTempLinked()
        case "level": startLevelLinked()
        case "mode": startModeLinked()
        default:
            if key.hasPrefix("hw:"), let k = HardwareLight(rawValue: String(key.dropFirst(3))) { applyHardware(k) }
            else if key.hasPrefix("sw:"), let e = SoftwareEffect(rawValue: String(key.dropFirst(3))) { start(e) }
        }
    }

    // MARK: 入口
    func applyHardware(_ kind: HardwareLight, color: RGB? = nil) {
        stopEngine()
        if let color { settings.solid = color }
        active = .hardware(kind)
        ble?.setLight(kind.mode(settings.solid.scaled(settings.brightness)))
    }

    func start(_ e: SoftwareEffect) { begin(.software(e)) }
    func startTempLinked() { begin(.tempLinked) }
    func startLevelLinked() { begin(.levelLinked) }
    func startModeLinked() {
        begin(.modeLinked)
        if let ble { applyModeLinked(ble.mode, ble.running) }
    }

    func stop() { stopEngine(); active = .none }
    func speedChanged() { if case .software = active { restartTimer() } }

    // MARK: 內部
    private func begin(_ a: Active) {
        stopEngine()
        frame = 0
        lastSignature = ""
        active = a
        restartTimer()
        tick()
    }

    private func stopEngine() { timer?.invalidate(); timer = nil }

    private func restartTimer() {
        timer?.invalidate(); timer = nil
        let interval: TimeInterval
        switch active {
        case .software: interval = max(0.6, settings.speed)
        case .tempLinked, .levelLinked: interval = 1.5
        default: return
        }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in self?.tick() }
    }

    private func tick() {
        guard let ble, ble.connected else { return }
        switch active {
        case .software(let e):
            let c = LightFrames.frame(e, index: frame, colors: settings.colors, solid: settings.solid)
            if ble.sendLightFrame(c.scaled(settings.brightness)) { frame += 1 }
        case .tempLinked:
            guard let t = ble.temperatureC else { return }
            sendOnChange("t", .breathMono(rgb: LightFrames.tempBandColor(t).scaled(settings.brightness).tuple))
        case .levelLinked:
            let n = CoolerProtocol.fanLevelValues.count
            let c: RGB
            switch ble.mode {
            case .manual(let l): c = LightFrames.levelColor(level: l, count: n)
            case .boost: c = LightFrames.levelColor(level: n - 1, count: n)
            case .smart: c = LightFrames.levelColor(level: n / 2, count: n)
            case .idle: c = LightFrames.levelColor(level: 0, count: n)
            }
            sendOnChange("l", .solid(rgb: c.scaled(settings.brightness).tuple))
        default: break
        }
    }

    private func sendOnChange(_ tag: String, _ mode: LightMode) {
        let payload = CoolerProtocol.lightPayload(mode)
        let sig = tag + payload.map(String.init).joined(separator: ",")
        guard sig != lastSignature else { return }
        lastSignature = sig
        ble?.setLight(mode)
    }

    private func applyModeLinked(_ mode: CoolerWorkMode, _ running: Bool) {
        let cfg: LinkedLight
        if !running { cfg = settings.linkOff } else {
            switch mode {
            case .smart: cfg = settings.linkSmart
            case .boost: cfg = settings.linkBoost
            case .manual, .idle: cfg = settings.linkManual
            }
        }
        sendOnChange("m", cfg.kind.mode(cfg.color.scaled(settings.brightness)))
    }

    private func save() {
        if let d = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(d, forKey: Self.key) }
    }
}
