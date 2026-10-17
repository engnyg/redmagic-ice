import Foundation
import CryptoKit

/// Telink BLE OTA 協議(取自冰環 2.10.46 的 TelinkOtaProtocol / TelinkOtaService)。
///   服務 00010203-0405-0607-0809-0a0b0c0d1912,特徵 00010203-0405-0607-0809-0a0b0c0d2b12(無回應寫入 + 通知)
///   1. 寫 `00 FF`                     開始
///   2. 逐包寫入 20 位元組:[序號 lo, 序號 hi, 16 位元組資料(不足補 FF), CRC16 lo, CRC16 hi]
///   3. 寫結束包 `02 FF idx lo hi ~idx lo hi 00…`(idx = 最後一包序號)
///   4. 設備通知 `06 FF 00` 表示校驗成功(非 0 為錯誤碼),隨後重啟
enum TelinkOTA {
    static let serviceUUID = "00010203-0405-0607-0809-0A0B0C0D1912"
    static let characteristicUUID = "00010203-0405-0607-0809-0A0B0C0D2B12"
    static let maxSize = 126_976
    static let startCommand = Data([0x00, 0xFF])
    /// 標準 Telink 的 OTA_START。冰環 X 在 `00 FF` 之後一定會再寫 `01 FF` 才開始送資料;
    /// 只送 `00 FF` 的話設備不會進入接收狀態(實測在約 1% 時被設備斷線)。
    static let startCommand2 = Data([0x01, 0xFF])
    static let startCommands = [startCommand, startCommand2]

    enum ImageError: LocalizedError {
        case badSize, noMagic, lengthMismatch, badCRC
        var errorDescription: String? {
            switch self {
            case .badSize: return "不是本設備支援的 Telink BIN 長度"
            case .noMagic: return "缺少 Telink KNLT 檔案標識"
            case .lengthMismatch: return "BIN 檔頭記錄的長度與實際長度不一致"
            case .badCRC: return "BIN CRC32 校驗失敗(檔案可能損壞)"
            }
        }
    }

    static func u32(_ b: [UInt8], _ offset: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { $0 | (UInt32(b[offset + $1]) << UInt32($1 * 8)) }
    }

    /// 標準 CRC32(多項式 0xEDB88320),等同 java.util.zip.CRC32
    static func crc32(_ bytes: ArraySlice<UInt8>) -> UInt32 {
        var table = [UInt32](repeating: 0, count: 256)
        for i in 0..<256 {
            var c = UInt32(i)
            for _ in 0..<8 { c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1) }
            table[i] = c
        }
        var crc: UInt32 = 0xFFFF_FFFF
        for b in bytes { crc = table[Int((crc ^ UInt32(b)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFF_FFFF
    }

    /// 與原版相同的檔案驗證:長度、KNLT 標識、檔頭長度欄位、尾端 CRC32(取補數)
    static func validate(_ data: Data) throws {
        let b = [UInt8](data)
        guard b.count >= 1024, b.count < maxSize, b.count % 16 == 4 else { throw ImageError.badSize }
        guard Array(b[8..<12]) == [0x4B, 0x4E, 0x4C, 0x54] else { throw ImageError.noMagic }   // "KNLT"
        guard Int(u32(b, 24)) == b.count else { throw ImageError.lengthMismatch }
        let crc = crc32(b[0..<(b.count - 4)]) ^ 0xFFFF_FFFF
        guard u32(b, b.count - 4) == crc else { throw ImageError.badCRC }
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// CRC16(多項式 0xA001,初值 0xFFFF)
    static func crc16(_ bytes: [UInt8], length: Int) -> UInt16 {
        var crc: UInt32 = 0xFFFF
        for i in 0..<length {
            crc ^= UInt32(bytes[i])
            for _ in 0..<8 { crc = (crc & 1) != 0 ? ((crc >> 1) ^ 0xA001) : (crc >> 1) }
        }
        return UInt16(crc & 0xFFFF)
    }

    static func packetCount(_ data: Data) -> Int { (data.count + 15) / 16 }

    static func packet(_ data: Data, index: Int) -> Data {
        precondition(index >= 0 && index < packetCount(data))
        var p = [UInt8](repeating: 0xFF, count: 20)
        p[0] = UInt8(index & 0xFF)
        p[1] = UInt8((index >> 8) & 0xFF)
        let b = [UInt8](data)
        let start = index * 16, end = min(start + 16, b.count)
        for (k, v) in b[start..<end].enumerated() { p[2 + k] = v }
        let crc = crc16(p, length: 18)
        p[18] = UInt8(crc & 0xFF)
        p[19] = UInt8(crc >> 8)
        return Data(p)
    }

    static func endPacket(lastIndex: Int) -> Data {
        precondition(lastIndex >= 0 && lastIndex < 65535)
        let inv = UInt16(truncatingIfNeeded: ~lastIndex)
        var p = [UInt8](repeating: 0, count: 20)
        p[0] = 0x02; p[1] = 0xFF
        p[2] = UInt8(lastIndex & 0xFF); p[3] = UInt8((lastIndex >> 8) & 0xFF)
        p[4] = UInt8(inv & 0xFF); p[5] = UInt8(inv >> 8)
        return Data(p)
    }

    /// 全部要依序寫入的封包:開始(2 個命令) + 資料 + 結束
    static func frames(for data: Data) -> [Data] {
        let n = packetCount(data)
        return startCommands + (0..<n).map { packet(data, index: $0) } + [endPacket(lastIndex: n - 1)]
    }
}
