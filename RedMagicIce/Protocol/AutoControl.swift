import Foundation

struct CurvePoint: Codable, Equatable {
    var temp: Double
    var level: Double      // 1...10(可為小數,取最接近的整數檔)
}

/// 溫度 → 檔位曲線(線性插值,兩端取端點值)。
struct TempCurve: Codable, Equatable {
    var points: [CurvePoint]

    /// 自由變頻:依散熱器(背夾)溫度。散熱器溫度越高代表負載越大,檔位越高。
    static let freeDefault = TempCurve(points: [
        .init(temp: -5, level: 1), .init(temp: 0, level: 2), .init(temp: 5, level: 3), .init(temp: 10, level: 4),
        .init(temp: 15, level: 6), .init(temp: 20, level: 8), .init(temp: 25, level: 10),
    ])

    /// 電池溫控:原版 9 個門檻 34…50℃ 每 2℃ 升一檔。
    static let batteryDefault = TempCurve(points: [
        .init(temp: 32, level: 1), .init(temp: 34, level: 2), .init(temp: 36, level: 3), .init(temp: 38, level: 4),
        .init(temp: 40, level: 5), .init(temp: 42, level: 6), .init(temp: 44, level: 7), .init(temp: 46, level: 8),
        .init(temp: 48, level: 9), .init(temp: 50, level: 10),
    ])

    func level(at t: Double) -> Double {
        let p = points.sorted { $0.temp < $1.temp }
        guard let first = p.first, let last = p.last else { return 1 }
        if t <= first.temp { return first.level }
        if t >= last.temp { return last.level }
        for i in 0..<(p.count - 1) {
            let a = p[i], b = p[i + 1]
            if t >= a.temp && t <= b.temp {
                if b.temp == a.temp { return b.level }
                return a.level + (b.level - a.level) * (t - a.temp) / (b.temp - a.temp)
            }
        }
        return last.level
    }
}

enum AutoLogic {
    static let levelCount = 10

    /// 曲線 → 檔位 index(0...9)。目標與目前檔位相差不到 0.55 時保持不動,避免頻繁切換(與原版一致)。
    static func curveIndex(curve: TempCurve, temp: Double, current: Int?) -> Int {
        let target = min(max(curve.level(at: temp), 1), Double(levelCount))
        if let c = current, c >= 0, c < levelCount, abs(target - Double(c + 1)) < 0.55 { return c }
        return min(max(Int(target.rounded()), 1), levelCount) - 1
    }

    /// 目標溫度控制:超出目標越多,檔位越高(門檻與原版一致:1/2/4/6/8/10℃ → 0/1/2/4/6/8/9)。
    static func targetBaseIndex(diff: Double) -> Int {
        switch diff {
        case ...1: return 0
        case ...2: return 1
        case ...4: return 2
        case ...6: return 4
        case ...8: return 6
        case ...10: return 8
        default: return 9
        }
    }

    /// 加入遲滯:升檔照原門檻,降檔要多降 0.7℃ 才生效。
    static func targetIndex(cooler: Double, target: Double, current: Int?) -> Int {
        let diff = cooler - target
        let up = targetBaseIndex(diff: diff)
        guard let c = current else { return up }
        if up > c { return up }
        let down = targetBaseIndex(diff: diff + 0.7)
        return down < c ? down : c
    }

    /// iOS 不開放電池溫度,以系統熱狀態估算。
    static func estimatedTemp(_ s: ProcessInfo.ThermalState) -> Double {
        switch s {
        case .nominal: return 33
        case .fair: return 38
        case .serious: return 44
        case .critical: return 50
        @unknown default: return 38
        }
    }

    static func thermalName(_ s: ProcessInfo.ThermalState) -> String {
        switch s {
        case .nominal: return "正常"
        case .fair: return "輕微發熱"
        case .serious: return "嚴重發熱"
        case .critical: return "危急"
        @unknown default: return "未知"
        }
    }
}
