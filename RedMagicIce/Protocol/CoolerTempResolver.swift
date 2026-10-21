import Foundation

/// 散熱器溫度有兩個來源:1015 狀態包(`04 xx`,8 Pro 要 −6)與 1014 特徵(直接讀)。
/// 兩者可能差 6 度;若誰最後到就顯示誰,數字會在兩個值之間來回跳。
/// 冰環 2.10.46 的 updateCoolerTempCompareText:8 Pro 以 1015(校正後)為主、1014 只在 1015 逾時才備用;
/// 其他機型相反。這裡照同樣的優先順序,並在兩邊都新鮮時學習兩者的差,讓備用來源不會造成跳動。
struct CoolerTempResolver {
    static let freshSeconds: TimeInterval = 10
    static let offset1015: Float = 6

    private var raw1015: (value: Float, at: TimeInterval)?
    private var raw1014: (value: Float, at: TimeInterval)?
    /// 1014 − 校正後 1015(兩邊同時新鮮時更新)
    private(set) var learnedDelta: Float?

    mutating func note1015(raw: Float, now: TimeInterval) { raw1015 = (raw, now) }
    mutating func note1014(_ v: Float, now: TimeInterval) { raw1014 = (v, now) }

    private func corrected1015(applyOffset: Bool) -> Float? {
        raw1015.map { applyOffset ? $0.value - Self.offset1015 : $0.value }
    }
    private func fresh(_ s: (value: Float, at: TimeInterval)?, _ now: TimeInterval) -> Float? {
        guard let s, now - s.at <= Self.freshSeconds else { return nil }
        return s.value
    }

    /// 1015 的原始值是否已到下限 0(此時只代表「≤ −6°C」)
    func statusAtFloor(now: TimeInterval) -> Bool {
        guard let raw = fresh(raw1015, now) else { return false }
        return raw <= 0
    }

    /// 兩個來源差距(1014 − 校正後 1015),兩邊都新鮮時才有值
    func disagreement(applyOffset: Bool, now: TimeInterval) -> Float? {
        guard fresh(raw1015, now) != nil, let b = fresh(raw1014, now), let a = corrected1015(applyOffset: applyOffset) else { return nil }
        return b - a
    }

    mutating func resolve(applyOffset: Bool, preferStatus: Bool, now: TimeInterval) -> Float? {
        let s = fresh(raw1015, now).flatMap { _ in corrected1015(applyOffset: applyOffset) }
        let d = fresh(raw1014, now)
        if let s, let d, abs(d - s) <= 12 { learnedDelta = d - s }
        if preferStatus {
            // 1015 是 `溫度+6` 的無號位元組,到 0 就停在下限(−6°C);比下限更冷時它不會再往下。
            // 這時改看 1014(扣掉學到的差),取較低的那個,讓顯示能低於 −6。
            if let s, let raw = fresh(raw1015, now), raw <= 0, let d {
                return min(s, d - (learnedDelta ?? 0))
            }
            if let s { return s }
            if let d { return d - (learnedDelta ?? 0) }
        } else {
            if let d { return d }
            if let s { return s }
        }
        return nil
    }
}
