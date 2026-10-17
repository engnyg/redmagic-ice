import Foundation

/// 已知的紅魔 8 Pro 韌體(以 SHA-256 辨識)。檔案本身內建於 App 包的 Firmware/(見 Firmware/FIRMWARE_NOTICE.md):
/// 韌體屬努比亞或冰環作者所有,原樣收錄;也可自行匯入其他檔案到「韌體庫」。
struct KnownFirmware: Identifiable, Equatable {
    enum Kind: String { case official, newLight, overclock }

    let sha256: String
    let title: String
    let version: String
    let kind: Kind
    let size: Int
    let note: String
    var id: String { sha256 }

    var kindName: String {
        switch kind {
        case .official: return "官方"
        case .newLight: return "新燈效"
        case .overclock: return "超頻(第三方修改)"
        }
    }
}

enum FirmwareCatalog {
    static let known: [KnownFirmware] = [
        .init(sha256: "7f7219630f7ca86d4d72abc5fd99e530655eae86bf05ca5e4407f25fd36b3148",
              title: "SRQ_8PRO", version: "V8.4.7", kind: .official, size: 51364,
              note: "官方固件(合集標示)。首次測試刷寫流程時,建議先用這個。"),
        .init(sha256: "b6ae7340b2b1ff4e896252070af22c0492313eb41770c71344cfbe6da86f6f6f",
              title: "SRQ_8PRO", version: "V8.5.2 R2", kind: .newLight, size: 54708,
              note: "新燈效固件(合集標示)。支援逐顆燈珠與 8 種內建新燈效。第三方製作,非官方。"),
        .init(sha256: "3db37337196a70fbde1fa94bc376aa8c689184ee293535e247ea85c049bcff74",
              title: "SRQ_8PRO", version: "V8.5.3 R2", kind: .overclock, size: 54772,
              note: "合集把它放在「超頻固件」資料夾,原作者標註「請謹慎使用,風險自擔」。同樣支援新燈效。"),
        .init(sha256: "2ef552d1ea9b5fa2a453ec79bcb3f8b7500a080b2a0a5ef5762ef04de4926542",
              title: "8.4.9 MaxFan", version: "V8.4.9", kind: .overclock, size: 51364,
              note: "超頻固件(合集標示),會突破風扇出廠限制。原作者標註「請謹慎使用,風險自擔」。"),
        .init(sha256: "4d8f37960e9984f4e6b2fddce88f7dafc70b1964760d3677e899f8401dc74423",
              title: "8Pro 基於 8.2.4 超頻", version: "V8.2.5", kind: .overclock, size: 52772,
              note: "超頻固件(合集標示),版本較舊。原作者標註「請謹慎使用,風險自擔」。"),
        .init(sha256: "1370c3f5dde5767593ff30a62dbac6d791ff193f93009e5a9dcd7b785b640df9",
              title: "8Pro 超頻", version: "V8.4.3", kind: .overclock, size: 50676,
              note: "超頻固件(合集標示),原作者標註「請謹慎使用,風險自擔」。"),
    ]

    static func identify(sha256: String) -> KnownFirmware? {
        known.first { $0.sha256 == sha256.lowercased() }
    }
}
