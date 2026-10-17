import Foundation

/// 固件內建 8 種燈效的預覽模擬(只在 App 畫面上畫,不會送給設備)。
/// 依 8.5.2 效果引擎的結構(docs/PROTOCOL.md「內建燈效引擎」)推算:
/// 一幀的時間 = `period` × 4.096 ms(系統計時器高 16 位元),效果 1 的亮相位用 period/3。
/// 已對照反組譯確認:1、3、4、6、7。2 依「沿一圈平均分布色索引再旋轉」推算;
/// 5、8 沒讀完,只是外觀近似,實機可能不同。
enum FirmwareEffectSimulator {
    static let tick = 0.004096
    static let exactEffects: Set<Int> = [1, 3, 4, 6, 7]

    static func frame(effect: Int, palette: [RGB], speed: Int, brightness: Int, time: Double) -> [RGB] {
        let n0 = FirmwareLight.ledCount
        guard !palette.isEmpty else { return Array(repeating: .black, count: n0) }
        let colors = (palette.count == 1 ? [palette[0], palette[0]] : palette)
            .map { FirmwareLight.limit(FirmwareLight.scale($0, brightness: brightness)) }
        let n = colors.count
        let period = Double(FirmwareLight.period(speed: speed, effect: effect))
        let stepDur = max(period, 3) * tick
        let step = Int(max(time, 0) / stepDur)
        var out = [RGB](repeating: .black, count: n0)
        func wrap(_ i: Int) -> Int { ((i % n0) + n0) % n0 }
        func color(_ i: Int) -> RGB { colors[((i % n) + n) % n] }

        switch effect {
        case 1: // 跳動:全環亮 period/3,再全暗 period,然後換色
            let on = max((period / 3).rounded(.down), 3), off = max(period, 3)
            let cycle = (on + off) * tick
            let t = max(time, 0)
            let k = Int(t / cycle)
            if t - Double(k) * cycle < on * tick { out = Array(repeating: color(k), count: n0) }
        case 2: // 多色旋轉:色索引沿一圈平均分布,每幀轉一格
            for i in 0..<n0 { out[i] = colors[((i + step) % n0) * n / n0] }
        case 3: // 切換漸變:16 步在相鄰兩色之間插值
            let idx = (step / 16) % n, s = step % 16
            out = Array(repeating: RGB.lerp(color(idx), color(idx + 1), Double(s) / 16), count: n0)
        case 4: // 碰撞:一個 3 顆的彗星往前、一個 2 顆的往回,每圈換色
            let idx = (step / n0) % n, p = step % n0, q = wrap(8 - step)
            for d in 0..<3 { out[wrap(p - d)] = color(idx) }
            out[q] = color(idx + 1); out[wrap(q + 1)] = color(idx + 1)
        case 5: // 賽博朋克(近似):4 顆一段的色塊旋轉
            for i in 0..<n0 { out[i] = color(((i + step) % n0) / 4) }
        case 6: // 多彩跑馬:頭亮、尾巴 ×5/8、×5/16,色索引每 2 幀前進一格
            let p = step % n0, idx = (step / 2) % n
            out[p] = color(idx)
            out[wrap(p - 1)] = color(idx + 1).scaled(0.625)
            out[wrap(p - 2)] = color(idx + 2).scaled(0.3125)
        case 7: // 環形流水:先從 0 填滿到 15,再從頭擦除,然後換色
            let idx = (step / 32) % n, s = step % 32
            for i in 0..<n0 {
                let lit = s < 16 ? i <= s : (i >= s - 15 && s < 31)
                if lit { out[i] = color(idx) }
            }
        case 8: // 幻彩雙追光(近似):兩個對向彗星,頭 1、尾 1/2、1/4
            let idx = (step / n0) % n, p = step % n0
            for base in [p, wrap(p + 8)] {
                out[base] = color(idx)
                out[wrap(base - 1)] = color(idx + 1).scaled(0.5)
                out[wrap(base - 2)] = color(idx + 1).scaled(0.25)
            }
        default: break
        }
        return out
    }
}
