import Foundation

struct RGB: Equatable, Codable, Hashable {
    var r: UInt8, g: UInt8, b: UInt8
    static let black = RGB(r: 0, g: 0, b: 0)
    static let white = RGB(r: 255, g: 255, b: 255)
    var tuple: (UInt8, UInt8, UInt8) { (r, g, b) }

    func scaled(_ k: Double) -> RGB {
        let k = min(max(k, 0), 1)
        func s(_ v: UInt8) -> UInt8 { UInt8((Double(v) * k).rounded()) }
        return RGB(r: s(r), g: s(g), b: s(b))
    }

    static func lerp(_ a: RGB, _ b: RGB, _ t: Double) -> RGB {
        func m(_ x: UInt8, _ y: UInt8) -> UInt8 { UInt8(min(max((Double(x) + (Double(y) - Double(x)) * t).rounded(), 0), 255)) }
        return RGB(r: m(a.r, b.r), g: m(a.g, b.g), b: m(a.b, b.b))
    }

    /// 反向轉換:h 0..<360、s/v 0...1(灰階與黑色的 h 為 0)
    var hsv: (h: Double, s: Double, v: Double) {
        let rr = Double(r) / 255, gg = Double(g) / 255, bb = Double(b) / 255
        let mx = max(rr, gg, bb), mn = min(rr, gg, bb), d = mx - mn
        var h = 0.0
        if d > 0 {
            if mx == rr { h = (gg - bb) / d; if h < 0 { h += 6 } }
            else if mx == gg { h = (bb - rr) / d + 2 }
            else { h = (rr - gg) / d + 4 }
            h *= 60
        }
        return (h, mx == 0 ? 0 : d / mx, mx)
    }

    /// h: 0..<360, s/v: 0...1
    static func hsv(_ h: Double, _ s: Double, _ v: Double) -> RGB {
        let hh = ((h.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360) / 60
        let i = Int(hh) % 6
        let f = hh - hh.rounded(.down)
        let p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
        var r = 0.0, g = 0.0, b = 0.0
        switch i {
        case 0: r = v; g = t; b = p
        case 1: r = q; g = v; b = p
        case 2: r = p; g = v; b = t
        case 3: r = p; g = q; b = v
        case 4: r = t; g = p; b = v
        default: r = v; g = p; b = q
        }
        return RGB(r: UInt8((r * 255).rounded()), g: UInt8((g * 255).rounded()), b: UInt8((b * 255).rounded()))
    }
}

/// 由 App 逐幀傳送「常亮顏色」模擬的燈效。裝置韌體只有 6 種內建模式,
/// 原版 App 的「自定義炫彩」也是這樣做的(最快 600ms 一幀)。
enum SoftwareEffect: String, CaseIterable, Identifiable, Codable {
    case rainbow, colorCycle, gradient, softBreath, strobe, police
    var id: String { rawValue }
    var title: String {
        switch self {
        case .rainbow: return "彩虹"
        case .colorCycle: return "色彩迴圈"
        case .gradient: return "漸變"
        case .softBreath: return "柔和呼吸"
        case .strobe: return "頻閃"
        case .police: return "警燈"
        }
    }
    var symbol: String {
        switch self {
        case .rainbow: return "rainbow"
        case .colorCycle: return "arrow.triangle.2.circlepath"
        case .gradient: return "circle.lefthalf.filled"
        case .softBreath: return "wind"
        case .strobe: return "bolt.fill"
        case .police: return "light.beacon.max.fill"
        }
    }
    /// 是否使用「顏色序列」
    var usesColorList: Bool { self == .colorCycle || self == .gradient }
    /// 是否使用單一主色
    var usesSolidColor: Bool { self == .softBreath || self == .strobe }
}

enum LightFrames {
    static let defaultColors: [RGB] = [
        RGB(r: 255, g: 0, b: 0), RGB(r: 67, g: 135, b: 232), RGB(r: 255, g: 255, b: 255), RGB(r: 210, g: 68, b: 233),
    ]

    static func frame(_ e: SoftwareEffect, index i: Int, colors: [RGB], solid: RGB) -> RGB {
        let list = colors.isEmpty ? defaultColors : colors
        switch e {
        case .rainbow:
            return .hsv(Double(i) * 10, 1, 1)
        case .colorCycle:
            return list[i % list.count]
        case .gradient:
            if list.count == 1 { return list[0] }
            let seg = i / 5, step = i % 5            // 與原版一致:每段 5 幀插值
            return .lerp(list[seg % list.count], list[(seg + 1) % list.count], Double(step) / 5)
        case .softBreath:
            let phase = Double(i % 20) / 20
            return solid.scaled(0.12 + 0.88 * (0.5 - 0.5 * cos(2 * .pi * phase)))
        case .strobe:
            return i % 2 == 0 ? solid : .black
        case .police:
            return i % 2 == 0 ? RGB(r: 255, g: 0, b: 0) : RGB(r: 0, g: 60, b: 255)
        }
    }

    /// 散熱器(背夾製冷面)溫度 → 顏色。製冷面通常在 0~30°C、越製冷越低,
    /// 所以溫度越低越偏冰藍,散熱不足(偏熱)時轉紅;0°C 以下為冰白,提醒注意凝露。
    static let tempBands: [(below: Float, color: RGB, name: String)] = [
        (0, RGB(r: 190, g: 235, b: 255), "冰白"),
        (5, RGB(r: 67, g: 135, b: 232), "藍"),
        (10, RGB(r: 55, g: 200, b: 187), "青"),
        (15, RGB(r: 71, g: 215, b: 122), "綠"),
        (20, RGB(r: 255, g: 210, b: 26), "黃"),
        (25, RGB(r: 255, g: 117, b: 18), "橙"),
    ]

    static func tempBandColor(_ t: Float) -> RGB {
        tempBands.first { t < $0.below }?.color ?? RGB(r: 255, g: 0, b: 0)   // 25°C 以上:紅
    }

    /// 檔位 → 藍(低)到紅(高)
    static func levelColor(level: Int, count: Int) -> RGB {
        let n = max(count - 1, 1)
        return .hsv(210 * (1 - Double(min(max(level, 0), n)) / Double(n)), 1, 1)
    }
}
