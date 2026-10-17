import Foundation

/// 紅魔散熱器機型(冰環 2.10.9 的 CoolerDeviceProfiles):不同機型支援的功能與遙測格式不同。
enum CoolerModel: String {
    case rm5Pro, rm6Pro, rm8Pro, unknown

    var displayName: String {
        switch self {
        case .rm5Pro: return "紅魔散熱器 5 Pro"
        case .rm6Pro: return "紅魔散熱器 6 Pro 系列"
        case .rm8Pro: return "紅魔散熱器 8 Pro"
        case .unknown: return "紅魔散熱器"
        }
    }

    /// 固件內建智慧溫控(5 Pro 沒有,原版以 App 依電池溫度控制)
    var supportsFirmwareAutoTemp: Bool { self == .rm6Pro || self == .rm8Pro }
    /// 新版遙測(1015 的溫度/轉速/功率幀、1019 轉速、101A 功率、101F 保護)只有 8 Pro
    var supportsNewTelemetry: Bool { self == .rm8Pro }

    static func detect(name: String) -> CoolerModel {
        let s = name.trimmingCharacters(in: .whitespaces).lowercased()
        guard !s.isEmpty else { return .unknown }
        if s.contains("8pro") || s.contains("8 pro") { return .rm8Pro }
        if s == "pa1246" || s.contains("magcooler 6") || s.contains("6 pro") || s.contains("6pro") { return .rm6Pro }
        if s.contains("magcooler 5") || s.contains("5 pro") || s.contains("5pro") { return .rm5Pro }
        return .unknown
    }
}
