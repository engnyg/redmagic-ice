import Foundation

struct CurvePoint: Codable, Equatable {
    var temp: Double
    var level: Double      // 1...11(11 = 破壞神,僅在「自動啟用破壞神」開啟時生效)
}

/// 溫度 → 檔位曲線(線性插值,兩端取端點值)。
struct TempCurve: Codable, Equatable {
    var points: [CurvePoint]

    private static func make(_ temps: [Double], _ levels: [Double]) -> TempCurve {
        TempCurve(points: zip(temps, levels).map { CurvePoint(temp: $0, level: $1) })
    }

    // MARK: 自由變頻 3 組預設(冰環 2.10.9:每組 11 點;散熱器溫度越高檔位越高)
    static let preset1 = make([-5, -2, 1, 4, 7, 10, 13, 16, 19, 22, 25], [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 10])
    static let presetLowTemp = make([-25, -20, -15, -10, -5, 0, 5, 10, 15, 20, 25], [1, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
    static let presetDaily = make([-20, -15, -10, -5, 0, 5, 10, 15, 20, 25, 30], [1, 2, 2, 3, 4, 5, 6, 7, 8, 9, 10])
    static let presetNames = ["預設1", "低溫遊戲", "日常均衡"]
    static let factoryPresets: [TempCurve] = [preset1, presetLowTemp, presetDaily]
    static let freeDefault = preset1

    /// 電池溫控:官方 5 Pro 曲線(電池 33°C 起轉、35→約 3.7 檔、38→約 5.3 檔、40→約 7.5 檔、42°C 以上滿檔)
    static let batteryDefault = make([33, 35, 38, 40, 42], [1, 3.5, 5.5, 7.5, 10])

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

// MARK: - 溫控穩定器(移植自冰環 2.10.9 ThermalControlStabilizer)

/// 目標溫度控制:取最近 3 筆中位數 → 指數平滑 → 算出需求檔位 → 以遲滯、最短停留與升降限速穩定輸出。
struct ThermalStabilizer {
    struct Output: Equatable {
        var filtered: Float
        var desiredLevel: Float
        var outputIndex: Int          // 0...(maxLevel-1)
        var changed: Bool
        var reason: String
        var level: Int { outputIndex + 1 }
    }

    private var samples: [Float] = []
    private var ema: Float?
    private(set) var outputIndex = -1
    private var lastChangeMs: Int64 = 0
    private var lastChangeTemp: Float?
    private var targetC: Float?
    private var lastSeenMs: Int64 = 0

    static let alpha: Float = 0.55
    static let reverseHysteresisC: Float = 0.22
    static let minHoldMs: Int64 = 2400
    static let maxUpStep = 2
    static let maxDownStep = 1

    mutating func reset() { self = ThermalStabilizer() }

    /// maxLogicalLevel:10,或開啟「自動啟用破壞神」時為 11。
    mutating func decideCoolerTarget(measured: Float, target: Float, maxLogicalLevel: Int, nowMs: Int64) -> Output {
        let maxLevel = min(max(maxLogicalLevel, 1), 11)
        let maxIndex = maxLevel - 1

        // 取樣與平滑(目標改變或資料中斷超過 20 秒就重置)
        if let t = targetC, abs(t - target) > 0.01 {
            samples.removeAll(); ema = nil; outputIndex = -1; lastChangeMs = 0; lastChangeTemp = nil
        }
        targetC = target
        if lastSeenMs > 0, nowMs - lastSeenMs > 20_000 { samples.removeAll(); ema = nil }
        lastSeenMs = nowMs
        samples.append(measured)
        while samples.count > 3 { samples.removeFirst() }
        let median = samples.sorted()[samples.count / 2]
        ema = ema.map { $0 + (median - $0) * Self.alpha } ?? median
        let filtered = ema ?? measured

        let diff = filtered - target
        let desiredLevel = Self.coolerDesiredLevel(filtered: filtered, target: target, maxLevel: maxLevel)
        let desiredIndex = min(max(Int(desiredLevel.rounded()), 1), maxLevel) - 1
        let urgentUp = (target <= 5 && diff >= 1) || (desiredIndex - outputIndex >= 4)
        let urgentDown = filtered <= target - 2.5
        return stabilize(filtered: filtered, desiredLevel: desiredLevel, maxIndex: maxIndex, nowMs: nowMs,
                         urgentUp: urgentUp, urgentDown: urgentDown)
    }

    private mutating func stabilize(filtered: Float, desiredLevel: Float, maxIndex: Int, nowMs: Int64,
                                    urgentUp: Bool, urgentDown: Bool) -> Output {
        let maxLevel = maxIndex + 1
        let safe = min(max(desiredLevel, 1), Float(maxLevel))
        let desired = min(max(Int(safe.rounded()), 1), maxLevel) - 1
        let current = outputIndex
        func out(_ idx: Int, _ changed: Bool, _ why: String) -> Output {
            Output(filtered: filtered, desiredLevel: safe, outputIndex: idx, changed: changed, reason: why)
        }
        guard current >= 0, current <= maxIndex else {
            outputIndex = desired; lastChangeMs = nowMs; lastChangeTemp = filtered
            return out(desired, true, "initial")
        }
        if desired == current { return out(current, false, "stable") }
        let held = nowMs - lastChangeMs
        if desired > current {
            if !urgentUp, let lt = lastChangeTemp, filtered < lt + Self.reverseHysteresisC { return out(current, false, "up-hysteresis") }
            if !urgentUp, held < Self.minHoldMs { return out(current, false, "up-hold") }
            let next = (urgentUp && desired == maxIndex) ? maxIndex : min(desired, current + Self.maxUpStep)
            outputIndex = next; lastChangeMs = nowMs; lastChangeTemp = filtered
            return out(next, true, urgentUp ? "urgent-up" : "step-up")
        }
        if !urgentDown, let lt = lastChangeTemp, filtered > lt - Self.reverseHysteresisC { return out(current, false, "down-hysteresis") }
        if !urgentDown, held < Self.minHoldMs { return out(current, false, "down-hold") }
        let next = urgentDown ? desired : max(desired, current - Self.maxDownStep)
        outputIndex = next; lastChangeMs = nowMs; lastChangeTemp = filtered
        return out(next, true, urgentDown ? "urgent-down" : "step-down")
    }

    static func coolerDesiredLevel(filtered: Float, target: Float, maxLevel: Int) -> Float {
        let diff = filtered - target
        let maxL = Float(maxLevel)
        if target > 5 || diff < 1 {
            let errorDemand = min(interpolate(diff, xs: [0, 0.4, 0.8, 1.5, 3, 5, 6.5, 8], ys: [1, 2, 3, 5, 7, 9, 10, 11]), maxL)
            let nominalHold = min(max(max(20 - target, 0) / 4 + 1, 1), Float(min(10, maxLevel)))
            let holdDemand: Float = diff < -2.5 ? 1 : (diff < -0.8 ? max(nominalHold - 2, 1) : nominalHold)
            return min(max(max(errorDemand, holdDemand), 1), maxL)
        }
        return maxL     // 目標 ≤5°C 且已超出 1°C:直接滿檔
    }

    static func interpolate(_ x: Float, xs: [Float], ys: [Float]) -> Float {
        guard !xs.isEmpty, xs.count == ys.count else { return 1 }
        if x <= xs[0] { return ys[0] }
        for i in 0..<(xs.count - 1) where x >= xs[i] && x <= xs[i + 1] {
            let r = min(max((x - xs[i]) / max(xs[i + 1] - xs[i], 0.001), 0), 1)
            return ys[i] + (ys[i + 1] - ys[i]) * r
        }
        return ys[ys.count - 1]
    }
}

// MARK: - 自動啟用破壞神(移植自冰環 2.10.9 AutomaticCoolingLevelController)

/// 需求檔位超過 10.65 並持續 1.6 秒 → 進入第 11 檔(破壞神);降到 10 以下並持續 2.8 秒 → 退出。
struct AutoBoostGate {
    static let enterLevel: Float = 10.65
    static let exitLevel: Float = 10.0
    static let enterHoldMs: Int64 = 1600
    static let exitHoldMs: Int64 = 2800

    private(set) var boostActive = false
    private var initialized = false
    private var enterSince: Int64 = 0
    private var exitSince: Int64 = 0
    private var lastSeen: Int64 = 0

    mutating func reset() { self = AutoBoostGate() }

    /// 回傳輸出檔位 1...11(11 = 破壞神)
    mutating func resolve(requested: Float, boostEnabled: Bool, urgent: Bool, nowMs: Int64) -> Int {
        if lastSeen > 0, nowMs - lastSeen > 30_000 { enterSince = 0; exitSince = 0 }
        lastSeen = nowMs
        let request = min(max(requested, 1), boostEnabled ? 11 : 10)
        func normal() -> Int { min(max(Int(request.rounded()), 1), 10) }

        guard initialized else {
            initialized = true
            boostActive = boostEnabled && urgent && request >= Self.enterLevel
            return boostActive ? 11 : normal()
        }
        guard boostEnabled else {
            enterSince = 0; exitSince = 0; boostActive = false
            return normal()
        }
        if boostActive {
            if urgent || request > Self.exitLevel { exitSince = 0; return 11 }
            if exitSince == 0 { exitSince = nowMs }
            if nowMs - exitSince < Self.exitHoldMs { return 11 }
            boostActive = false; exitSince = 0; enterSince = 0
            return normal()
        }
        exitSince = 0
        if urgent && request >= Self.enterLevel { boostActive = true; enterSince = 0; return 11 }
        if request < Self.enterLevel { enterSince = 0; return normal() }
        if enterSince == 0 { enterSince = nowMs }
        if nowMs - enterSince >= Self.enterHoldMs { boostActive = true; enterSince = 0; return 11 }
        return 10
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
