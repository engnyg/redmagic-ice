import Foundation

/// 紅魔散熱器 BLE 協議(由 冰環 APK 2.8.91 逆向得出)。
/// 所有特徵均為 16 位 UUID(0000xxxx-0000-1000-8000-00805f9b34fb),寫入使用 "with response"。
enum CoolerChar: String, CaseIterable {
    case powerMode = "1011"   // 散熱開關: 02=開 03=關
    case fanMode = "1012"     // 手動檔位: 見 CoolerProtocol.fanLevelValues
    case light = "1013"       // 燈光: [模式, R, G, B]
    case temp = "1014"        // 散熱器溫度
    case status = "1015"      // 狀態包: [型別, 資料...]
    case logger = "1016"
    case boost = "1017"       // 破壞神: 01/00
    case autoTemp = "1018"    // 智慧溫控: 01/00
    case fanSpeed = "1019"    // 轉速(備用 101C)
    case power = "101A"       // 功率(備用 101D)
    case fanSpeedAlt = "101C"
    case powerAlt = "101D"
    case protection = "101F"  // 保護閾值
    case firmwareModule = "2A26"
    case firmwareMain = "2A28"
}

enum LightMode {
    case colorful, breathFull, breathMono(rgb: (UInt8, UInt8, UInt8)), solid(rgb: (UInt8, UInt8, UInt8)), off
}

struct LightPreset: Identifiable {
    let name: String
    let r: UInt8, g: UInt8, b: UInt8
    var id: String { name }
}

struct StatusUpdate: Equatable {
    var temperatureC: Float?
    var rpm: Int?
    var powerW: Int?
    /// true=執行, false=停機(1015=05 7F), nil=未知
    var running: Bool?
}

enum CoolerProtocol {
    static let fanLevelValues: [UInt8] = [40, 44, 46, 52, 58, 64, 68, 72, 76, 80]

    static let lightPresets: [LightPreset] = [
        .init(name: "紅", r: 255, g: 0, b: 0), .init(name: "橙", r: 255, g: 117, b: 18),
        .init(name: "黃", r: 255, g: 210, b: 26), .init(name: "綠", r: 71, g: 215, b: 122),
        .init(name: "青", r: 55, g: 200, b: 187), .init(name: "藍", r: 67, g: 135, b: 232),
        .init(name: "紫", r: 99, g: 101, b: 223), .init(name: "粉", r: 223, g: 74, b: 152),
        .init(name: "玫", r: 243, g: 63, b: 103), .init(name: "洋紅", r: 210, g: 68, b: 233),
        .init(name: "紫藍", r: 135, g: 91, b: 232), .init(name: "湖藍", r: 39, g: 166, b: 217),
        .init(name: "薄荷", r: 31, g: 184, b: 133), .init(name: "草綠", r: 124, g: 204, b: 22),
        .init(name: "白", r: 255, g: 255, b: 255),
    ]

    // MARK: 命令編碼
    static let powerOn = Data([0x02])
    static let powerOff = Data([0x03])
    static func flag(_ on: Bool) -> Data { Data([on ? 1 : 0]) }
    static func fanLevel(index: Int) -> Data {
        let i = min(max(index, 0), fanLevelValues.count - 1)
        return Data([fanLevelValues[i]])
    }

    static func lightPayload(_ mode: LightMode) -> Data {
        switch mode {
        case .colorful: return Data([1, 0, 0, 0])
        case .breathFull: return Data([2, 0, 0, 0])
        case .breathMono(let c): return Data([3, c.0, c.1, c.2])
        case .solid(let c): return Data([4, c.0, c.1, c.2])
        case .off: return Data([6, 0, 0, 0])      // 官方 App 抓包:關燈 = 06 00 00 00(05 為未知/保留,不要用)
        }
    }

    // MARK: 解析
    static func parseTemp(_ v: Data) -> Float? {
        let b = [UInt8](v)
        func ok(_ t: Float) -> Float? { (-40...80).contains(t) ? t : nil }
        if b.isEmpty { return nil }
        if b.count == 1 { return ok(Float(Int8(bitPattern: b[0]))) }
        if b[0] == 4 { return ok(Float(Int8(bitPattern: b[1]))) }   // 官方 847 狀態包
        let be = Int(b[0]) << 8 | Int(b[1]), le = Int(b[1]) << 8 | Int(b[0])
        func kelvin(_ r: Int) -> Float? { (230...360).contains(r) ? Float(r) - 273.15 : nil }
        func signed(_ r: Int) -> Float? { let s = r >= 0x8000 ? r - 0x10000 : r; return (-400...800).contains(s) ? Float(s) : nil }
        let candidates: [Float?] = [kelvin(be), kelvin(le), signed(be), signed(le), Float(be), Float(le)]
        return candidates.compactMap { $0 }.first { (-40...80).contains($0) }
    }

    /// 1015 狀態包 `04 xx`:顯示溫度 = xx − 6 °C。
    /// 官方 App 抓包(`04 03` → −3°C、`04 08` → 2°C)與冰環的 applyOfficialTempOffset 一致。
    static let statusTempOffset: Float = 6
    static func parseStatusTemp(_ v: Data) -> Float? {
        let b = [UInt8](v)
        guard b.count >= 2, b[0] == 4 else { return nil }
        let t = Float(Int8(bitPattern: b[1])) - statusTempOffset
        return (-40...80).contains(t) ? t : nil
    }

    static func parseRpm(_ v: Data) -> Int? {
        let b = [UInt8](v)
        if b.count >= 3 && b[0] == 8 { return Int(b[1]) << 8 | Int(b[2]) }
        if b.count >= 2 { return Int(b[0]) << 8 | Int(b[1]) }
        return nil
    }

    static func parsePower(_ v: Data) -> Int? {
        let b = [UInt8](v)
        if b.isEmpty { return nil }
        if b.count >= 2 && b[0] == 9 { return b[1] <= 80 ? Int(b[1]) : nil }
        return Int(b[0])
    }

    /// 1015 狀態包: 04=溫度 05=執行狀態 08=轉速 09=功率
    static func parseStatus(_ v: Data) -> StatusUpdate {
        let b = [UInt8](v)
        var u = StatusUpdate()
        guard let type = b.first else { return u }
        switch type {
        case 4: u.temperatureC = parseStatusTemp(v)
        case 5 where b.count >= 2:
            if b[1] == 0x7F { u.running = false } else if b[1] == 0x80 || b[1] == 0x00 { u.running = true }
        case 8: u.rpm = parseRpm(v)
        case 9: u.powerW = parsePower(v)
        default: break
        }
        return u
    }

    /// 與 Android 端 isLikelyMagcoolerName 一致
    static func isLikelyCoolerName(_ name: String) -> Bool {
        let s = name.trimmingCharacters(in: .whitespaces).lowercased()
        guard !s.isEmpty else { return false }
        if ["redmagic", "red magic", "nubia", "magcooler", "mag cooler", "jacket", "srq", "8pro"].contains(where: s.contains) { return true }
        return s.range(of: "(^|[^a-z0-9])rm[^a-z0-9]*8[^a-z0-9]*pro([^a-z0-9]|$)", options: .regularExpression) != nil
    }
}
