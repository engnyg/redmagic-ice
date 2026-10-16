import ActivityKit
import SwiftUI

/// App 與 Widget 擴充套件共用的即時動態(動態島 / 鎖屏)資料結構。
struct CoolerActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var temperatureC: Int?
        var rpm: Int?
        var powerW: Int?
        var running: Bool
        /// off / idle / manual / smart / boost
        var mode: String
        var level: Int?
        /// 自動溫控名稱(mode == "auto" 時使用)
        var autoName: String?

        var modeTitle: String {
            switch mode {
            case "manual": return level.map { "手動 \($0 + 1) 檔" } ?? "手動"
            case "auto": return "\(autoName ?? "自動") \((level ?? 0) + 1) 檔"
            case "smart": return "智慧溫控"
            case "boost": return "破壞神"
            case "idle": return "執行中"
            default: return "已關閉"
            }
        }

        var tint: Color {
            switch mode {
            case "boost": return .red
            case "smart": return .green
            case "auto": return .mint
            case "manual": return .cyan
            case "idle": return .blue
            default: return .gray
            }
        }

        var temperatureText: String { temperatureC.map { "\($0)°" } ?? "--" }
    }

    var deviceName: String
}
