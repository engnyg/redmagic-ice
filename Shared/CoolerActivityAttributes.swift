import ActivityKit
import SwiftUI

/// App 与 Widget 扩展共用的实时活动(灵动岛 / 锁屏)数据结构。
struct CoolerActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var temperatureC: Int?
        var rpm: Int?
        var powerW: Int?
        var running: Bool
        /// off / idle / manual / smart / boost
        var mode: String
        var level: Int?

        var modeTitle: String {
            switch mode {
            case "manual": return level.map { "手动 \($0 + 1) 档" } ?? "手动"
            case "smart": return "智能温控"
            case "boost": return "破坏神"
            case "idle": return "运行中"
            default: return "已关闭"
            }
        }

        var tint: Color {
            switch mode {
            case "boost": return .red
            case "smart": return .green
            case "manual": return .cyan
            case "idle": return .blue
            default: return .gray
            }
        }

        var temperatureText: String { temperatureC.map { "\($0)°" } ?? "--" }
    }

    var deviceName: String
}
