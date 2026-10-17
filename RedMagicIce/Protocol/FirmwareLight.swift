import Foundation

/// 紅魔 8 Pro 固件 8.5.2 / 8.5.3 的擴充燈光協議(由冰環 2.10.46 反編譯得出)。
/// 全部寫入 1013,固定 4 位元組:
///   F0 i R G / F1 i B 00     第 i 顆燈珠(0~15)的顏色,共 16 顆,一圈 32 筆
///   F5 n 00 00               內建燈效的調色盤顏色數
///   F2 k R G / F3 k B 00     調色盤第 k 色
///   F4 effect period maxW    啟動內建燈效(1~8)、週期、亮度上限;effect=0 為停止
///   F0 10 enable 00          桌搭模式開關(i=0x10 超出燈珠編號範圍,作為子命令)
enum FirmwareLight {
    static let ledCount = 16
    static let stop = Data([0xF4, 0, 0, 0])

    struct Effect: Identifiable, Equatable {
        let id: Int
        let name: String
        let defaultColors: [RGB]
    }

    static let effects: [Effect] = [
        .init(id: 1, name: "跳動", defaultColors: [RGB(r: 255, g: 54, b: 74), RGB(r: 67, g: 135, b: 232)]),
        .init(id: 2, name: "多色旋轉", defaultColors: [RGB(r: 255, g: 0, b: 0), RGB(r: 0, g: 255, b: 0), RGB(r: 255, g: 255, b: 0)]),
        .init(id: 3, name: "切換漸變", defaultColors: [RGB(r: 255, g: 75, b: 180), RGB(r: 82, g: 126, b: 255)]),
        .init(id: 4, name: "碰撞", defaultColors: [RGB(r: 0, g: 220, b: 255), RGB(r: 255, g: 60, b: 210)]),
        .init(id: 5, name: "賽博朋克", defaultColors: [RGB(r: 0, g: 229, b: 255), RGB(r: 255, g: 38, b: 190), RGB(r: 120, g: 80, b: 255)]),
        .init(id: 6, name: "多彩跑馬", defaultColors: [RGB(r: 255, g: 0, b: 0), RGB(r: 255, g: 120, b: 0), RGB(r: 255, g: 255, b: 0),
                                                      RGB(r: 0, g: 255, b: 0), RGB(r: 0, g: 255, b: 255), RGB(r: 0, g: 0, b: 255), RGB(r: 255, g: 0, b: 255)]),
        .init(id: 7, name: "環形流水", defaultColors: [RGB(r: 55, g: 126, b: 255), RGB(r: 0, g: 225, b: 255), RGB(r: 255, g: 255, b: 255)]),
        .init(id: 8, name: "幻彩雙追光", defaultColors: [RGB(r: 255, g: 42, b: 190), RGB(r: 0, g: 224, b: 255), RGB(r: 125, g: 82, b: 255)]),
    ]

    /// 只有紅魔 8 Pro 且主控固件(2A28)為 8.5.2 / 8.5.3 才支援
    static func isCapable(is8Pro: Bool, revision: String) -> Bool {
        guard is8Pro else { return false }
        return revision.range(of: "(?<![0-9.])v?8\\.5\\.[23](?![0-9.])", options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// 調色盤最多顏色數(支援的固件為 64)
    static let paletteCapacity = 64

    // MARK: 輸出安全(冰環的保守上限:RGB 總和 ≤ 382、亮度上限位元組 ≤ 127)
    static let maxRGBSum = 382
    static let maxWhiteChannel = 127

    static func limit(_ c: RGB) -> RGB {
        let total = Int(c.r) + Int(c.g) + Int(c.b)
        guard total > maxRGBSum else { return c }
        func ch(_ v: UInt8) -> UInt8 { UInt8(Int(v) * maxRGBSum / total) }
        return RGB(r: ch(c.r), g: ch(c.g), b: ch(c.b))
    }

    static func scale(_ c: RGB, brightness: Int) -> RGB {
        let b = min(max(brightness, 0), 100)
        func ch(_ v: UInt8) -> UInt8 { UInt8((Int(v) * b + 50) / 100) }
        return RGB(r: ch(c.r), g: ch(c.g), b: ch(c.b))
    }

    /// 速度 0~100 → 週期位元組(速度越快週期越短)
    static func period(speed: Int, effect: Int) -> Int {
        let ratio = 1.0 - Double(min(max(speed, 0), 100)) / 100.0
        if effect == 1 { return min(max(Int((pow(20.0, ratio) * 12).rounded()), 12), 240) }
        return min(max(Int((pow(8.0, ratio) * 3).rounded()), 3), 24)
    }

    // MARK: 封包
    /// 逐顆燈珠一整圈:16 顆 × 2 筆 = 32 筆
    static func pixelFrame(colors: [RGB], brightness: Int) -> [Data] {
        var cs = Array(colors.prefix(ledCount))
        while cs.count < ledCount { cs.append(.black) }
        var out: [Data] = []
        for (i, c0) in cs.enumerated() {
            let c = limit(scale(c0, brightness: brightness))
            out.append(Data([0xF0, UInt8(i), c.r, c.g]))
            out.append(Data([0xF1, UInt8(i), c.b, 0]))
        }
        return out
    }

    /// 內建燈效(1~8)設定與啟動
    static func configuration(effect: Int, colors: [RGB], speed: Int, brightness: Int) -> [Data]? {
        guard (1...8).contains(effect), !colors.isEmpty, colors.count <= paletteCapacity else { return nil }
        let palette = colors.count == 1 ? [colors[0], colors[0]] : colors
        var out: [Data] = [Data([0xF5, UInt8(palette.count), 0, 0])]
        for (k, c0) in palette.enumerated() {
            let c = limit(scale(c0, brightness: brightness))
            out.append(Data([0xF2, UInt8(k), c.r, c.g]))
            out.append(Data([0xF3, UInt8(k), c.b, 0]))
        }
        let cap = min(min(max(brightness, 0), 100) * 255 / 100, maxWhiteChannel)
        out.append(Data([0xF4, UInt8(effect), UInt8(period(speed: speed, effect: effect)), UInt8(cap)]))
        return out
    }

    static func desktopMode(enabled: Bool) -> Data { Data([0xF0, 0x10, enabled ? 1 : 0, 0]) }
}
