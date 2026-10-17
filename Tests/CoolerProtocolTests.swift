import XCTest
@testable import RedMagicIce

final class CoolerProtocolTests: XCTestCase {
    func testCommands() {
        XCTAssertEqual(CoolerProtocol.powerOn, Data([2]))
        XCTAssertEqual(CoolerProtocol.powerOff, Data([3]))
        XCTAssertEqual(CoolerProtocol.fanLevel(index: 0), Data([40]))
        XCTAssertEqual(CoolerProtocol.fanLevel(index: 99), Data([80]))
        XCTAssertEqual(CoolerProtocol.lightPayload(.solid(rgb: (1, 2, 3))), Data([4, 1, 2, 3]))
        XCTAssertEqual(CoolerProtocol.lightPayload(.off), Data([6, 0, 0, 0]))          // 官方抓包:06000000
        XCTAssertEqual(CoolerProtocol.lightPayload(.colorful), Data([1, 0, 0, 0]))
        XCTAssertEqual(CoolerProtocol.lightPayload(.breathFull), Data([2, 0, 0, 0]))
        XCTAssertEqual(CoolerProtocol.lightPayload(.solid(rgb: (255, 0, 0))), Data([0x04, 0xFF, 0x00, 0x00]))
    }

    func testStatusPackets() {
        // 官方抓包範例:04030000 → -3°C、04080000 → 2°C
        XCTAssertEqual(CoolerProtocol.parseStatus(Data([4, 3, 0, 0])).temperatureC, -3)
        XCTAssertEqual(CoolerProtocol.parseStatus(Data([4, 8, 0, 0])).temperatureC, 2)
        XCTAssertEqual(CoolerProtocol.parseStatus(Data([4, 25])).temperatureC, 19)
        XCTAssertEqual(CoolerProtocol.parseStatus(Data([8, 0x0B, 0xB8])).rpm, 3000)
        XCTAssertEqual(CoolerProtocol.parseStatus(Data([8, 0x13, 0xEC, 0])).rpm, 5100)     // 官方抓包 0813ec00
        XCTAssertEqual(CoolerProtocol.parseStatus(Data([9, 12])).powerW, 12)
        XCTAssertNil(CoolerProtocol.parseStatus(Data([9, 200])).powerW)
        XCTAssertEqual(CoolerProtocol.parseStatus(Data([5, 0x7F])).running, false)
        XCTAssertEqual(CoolerProtocol.parseStatus(Data([5, 0x80])).running, true)
    }

    func testDedicatedParsers() {
        XCTAssertEqual(CoolerProtocol.parseTemp(Data([30])), 30)
        XCTAssertNil(CoolerProtocol.parseTemp(Data([120])))
        XCTAssertEqual(CoolerProtocol.parseRpm(Data([0x04, 0x00])), 1024)
        XCTAssertEqual(CoolerProtocol.parsePower(Data([7])), 7)
    }

    func testNameMatching() {
        XCTAssertTrue(CoolerProtocol.isLikelyCoolerName("RedMagic Cooler"))
        XCTAssertTrue(CoolerProtocol.isLikelyCoolerName("RM 8 Pro"))
        XCTAssertFalse(CoolerProtocol.isLikelyCoolerName("AirPods"))
    }

    func testLightFrames() {
        let red = RGB(r: 255, g: 0, b: 0), blue = RGB(r: 0, g: 0, b: 255)
        XCTAssertEqual(LightFrames.frame(.colorCycle, index: 5, colors: [red, blue], solid: .white), blue)
        XCTAssertEqual(LightFrames.frame(.gradient, index: 0, colors: [red, blue], solid: .white), red)
        XCTAssertEqual(LightFrames.frame(.gradient, index: 5, colors: [red, blue], solid: .white), blue)
        XCTAssertEqual(LightFrames.frame(.strobe, index: 1, colors: [], solid: red), .black)
        XCTAssertEqual(LightFrames.frame(.rainbow, index: 0, colors: [], solid: .white), red)
        XCTAssertEqual(LightFrames.tempBandColor(30), red)                          // 偏熱
        XCTAssertEqual(LightFrames.tempBandColor(12), RGB(r: 71, g: 215, b: 122))   // 綠
        XCTAssertEqual(LightFrames.tempBandColor(3), RGB(r: 67, g: 135, b: 232))    // 藍
        XCTAssertEqual(LightFrames.tempBandColor(-2), RGB(r: 190, g: 235, b: 255))  // 冰白
        XCTAssertEqual(LightFrames.levelColor(level: 9, count: 10), red)
        XCTAssertEqual(RGB.white.scaled(0.5), RGB(r: 128, g: 128, b: 128))
    }

    func testAutoCurve() {
        let c = TempCurve.freeDefault                       // 預設1:11 點
        XCTAssertEqual(c.points.count, 11)
        XCTAssertEqual(TempCurve.presetNames.count, 3)
        XCTAssertEqual(TempCurve.factoryPresets.map { $0.points.count }, [11, 11, 11])
        XCTAssertEqual(c.level(at: -20), 1)
        XCTAssertEqual(c.level(at: 40), 10)
        XCTAssertEqual(c.level(at: 2.5), 3.5, accuracy: 0.001)   // (1,3)→(4,4) 之間
        XCTAssertEqual(AutoLogic.curveIndex(curve: c, temp: 25, current: nil), 9)
        // 遲滯:目標約 3.17 檔,目前 3 檔(差 < 0.55)保持不動
        XCTAssertEqual(AutoLogic.curveIndex(curve: c, temp: 1.5, current: 2), 2)
        // 官方電池曲線:33°C 起轉,42°C 以上滿檔
        XCTAssertEqual(TempCurve.batteryDefault.level(at: 30), 1)
        XCTAssertEqual(TempCurve.batteryDefault.level(at: 38), 5.5, accuracy: 0.001)
        XCTAssertEqual(AutoLogic.curveIndex(curve: .batteryDefault, temp: 50, current: nil), 9)
        XCTAssertEqual(AutoLogic.curveIndex(curve: .batteryDefault, temp: 30, current: nil), 0)
    }

    func testThermalStabilizer() {
        var s = ThermalStabilizer()
        // 目標 18,剛好在目標:基本維持 2 檔(nominalHold = (20-18)/4+1 = 1.5)
        var o = s.decideCoolerTarget(measured: 18, target: 18, maxLogicalLevel: 10, nowMs: 0)
        XCTAssertEqual(o.reason, "initial"); XCTAssertEqual(o.level, 2)
        // 溫度突升到 22:平滑後約 20.2°C,需求約 6 檔,與目前差 ≥4 檔 → 急升,但一次最多升 2 檔
        o = s.decideCoolerTarget(measured: 22, target: 18, maxLogicalLevel: 10, nowMs: 3000)
        XCTAssertEqual(o.reason, "urgent-up"); XCTAssertEqual(o.level, 4)
        // 目標 ≤5°C 且超出 1°C:直接滿檔
        var cold = ThermalStabilizer()
        o = cold.decideCoolerTarget(measured: 4.5, target: 3, maxLogicalLevel: 10, nowMs: 0)
        XCTAssertEqual(o.level, 10)
        // 改變目標會重置狀態
        o = s.decideCoolerTarget(measured: 18, target: 10, maxLogicalLevel: 10, nowMs: 6000)
        XCTAssertEqual(o.reason, "initial")
    }

    func testAutoBoostGate() {
        var g = AutoBoostGate()
        XCTAssertEqual(g.resolve(requested: 11, boostEnabled: true, urgent: false, nowMs: 0), 10)      // 初始
        XCTAssertEqual(g.resolve(requested: 11, boostEnabled: true, urgent: false, nowMs: 100), 10)    // 計時開始
        XCTAssertEqual(g.resolve(requested: 11, boostEnabled: true, urgent: false, nowMs: 1800), 11)   // 持續 ≥1.6s → 破壞神
        XCTAssertEqual(g.resolve(requested: 9, boostEnabled: true, urgent: false, nowMs: 2000), 11)    // 退出需持續 2.8s
        XCTAssertEqual(g.resolve(requested: 9, boostEnabled: true, urgent: false, nowMs: 5000), 9)
        var off = AutoBoostGate()
        _ = off.resolve(requested: 11, boostEnabled: false, urgent: false, nowMs: 0)
        XCTAssertEqual(off.resolve(requested: 11, boostEnabled: false, urgent: false, nowMs: 9000), 10) // 未啟用:永不超過 10
    }

    func testCoolerModel() {
        XCTAssertEqual(CoolerModel.detect(name: "RM Magcooler 8pro"), .rm8Pro)
        XCTAssertEqual(CoolerModel.detect(name: "RM Magcooler 6pro"), .rm6Pro)
        XCTAssertEqual(CoolerModel.detect(name: "PA1246"), .rm6Pro)
        XCTAssertEqual(CoolerModel.detect(name: "RM Magcooler 5pro"), .rm5Pro)
        XCTAssertEqual(CoolerModel.detect(name: "AirPods"), .unknown)
        XCTAssertTrue(CoolerModel.rm8Pro.supportsNewTelemetry)
        XCTAssertFalse(CoolerModel.rm5Pro.supportsFirmwareAutoTemp)
        XCTAssertTrue(CoolerProtocol.isLikelyCoolerName("PA1246"))
    }

    func testFirmwarePixelFrame() {
        // 冰環 2.10.46 的 F0/F1 逐燈珠協議:每顆 [F0 i R G] + [F1 i B 00],共 32 筆
        var colors = [RGB](repeating: .black, count: 16)
        colors[0] = RGB(r: 255, g: 0, b: 0)
        colors[1] = .white                                    // 總和 765 > 382 → 等比例壓到 127
        let f = FirmwareLight.pixelFrame(colors: colors, brightness: 100)
        XCTAssertEqual(f.count, 32)
        XCTAssertEqual(f[0], Data([0xF0, 0, 0xFF, 0x00]))
        XCTAssertEqual(f[1], Data([0xF1, 0, 0x00, 0x00]))
        XCTAssertEqual(f[2], Data([0xF0, 1, 0x7F, 0x7F]))
        XCTAssertEqual(f[3], Data([0xF1, 1, 0x7F, 0x00]))
        XCTAssertEqual(f[30], Data([0xF0, 15, 0, 0]))
        // 亮度 50%:(255*50+50)/100 = 128
        XCTAssertEqual(FirmwareLight.pixelFrame(colors: colors, brightness: 50)[0], Data([0xF0, 0, 128, 0]))
    }

    func testFirmwareEffectConfiguration() {
        let p = FirmwareLight.configuration(effect: 6, colors: [RGB(r: 255, g: 0, b: 0), RGB(r: 0, g: 255, b: 0)], speed: 50, brightness: 100)!
        XCTAssertEqual(p[0], Data([0xF5, 2, 0, 0]))
        XCTAssertEqual(p[1], Data([0xF2, 0, 0xFF, 0x00]))
        XCTAssertEqual(p[2], Data([0xF3, 0, 0x00, 0]))
        XCTAssertEqual(p[3], Data([0xF2, 1, 0x00, 0xFF]))
        XCTAssertEqual(p.last, Data([0xF4, 6, 8, 0x7F]))                       // 週期 round(8^0.5*3)=8、亮度上限 127
        XCTAssertEqual(FirmwareLight.configuration(effect: 3, colors: [.white], speed: 0, brightness: 40)![0], Data([0xF5, 2, 0, 0]))  // 單色複製成 2 色
        XCTAssertNil(FirmwareLight.configuration(effect: 9, colors: [.white], speed: 0, brightness: 40))
        XCTAssertNil(FirmwareLight.configuration(effect: 1, colors: [], speed: 0, brightness: 40))
        XCTAssertEqual(FirmwareLight.stop, Data([0xF4, 0, 0, 0]))
        XCTAssertEqual(FirmwareLight.desktopMode(enabled: true), Data([0xF0, 0x10, 1, 0]))
        XCTAssertEqual(FirmwareLight.period(speed: 100, effect: 1), 12)
        XCTAssertEqual(FirmwareLight.period(speed: 0, effect: 1), 240)
        XCTAssertEqual(FirmwareLight.period(speed: 0, effect: 2), 24)
        XCTAssertEqual(FirmwareLight.effects.count, 8)
    }

    func testFirmwareCapability() {
        XCTAssertTrue(FirmwareLight.isCapable(is8Pro: true, revision: "V8.5.2"))
        XCTAssertTrue(FirmwareLight.isCapable(is8Pro: true, revision: "8.5.3"))
        XCTAssertFalse(FirmwareLight.isCapable(is8Pro: true, revision: "V8.5.1"))
        XCTAssertFalse(FirmwareLight.isCapable(is8Pro: true, revision: "V8.5.20"))
        XCTAssertFalse(FirmwareLight.isCapable(is8Pro: true, revision: "18.5.2"))
        XCTAssertFalse(FirmwareLight.isCapable(is8Pro: false, revision: "V8.5.2"))
        XCTAssertEqual(FirmwareLight.limit(RGB(r: 100, g: 100, b: 100)), RGB(r: 100, g: 100, b: 100))
    }

    func testTelinkOTAProtocol() throws {
        // CRC16(0xA001, init 0xFFFF)標準測試向量
        XCTAssertEqual(TelinkOTA.crc16(Array("123456789".utf8), length: 9), 0x4B37)
        // 標準 CRC32 測試向量
        XCTAssertEqual(TelinkOTA.crc32(Array("123456789".utf8)[...]), 0xCBF43926)

        // 組一個合法映像:1028 位元組(1028 % 16 == 4)、KNLT 標識、長度欄位、尾端 CRC32 補數
        var img = [UInt8](repeating: 0x5A, count: 1028)
        img[8] = 0x4B; img[9] = 0x4E; img[10] = 0x4C; img[11] = 0x54
        img[24] = UInt8(1028 & 0xFF); img[25] = UInt8(1028 >> 8); img[26] = 0; img[27] = 0
        let crc = TelinkOTA.crc32(img[0..<1024]) ^ 0xFFFF_FFFF
        for i in 0..<4 { img[1024 + i] = UInt8((crc >> UInt32(i * 8)) & 0xFF) }
        XCTAssertNoThrow(try TelinkOTA.validate(Data(img)))

        var bad = img; bad[100] ^= 0xFF
        XCTAssertThrowsError(try TelinkOTA.validate(Data(bad)))                     // CRC 不符
        var noMagic = img; noMagic[8] = 0
        XCTAssertThrowsError(try TelinkOTA.validate(Data(noMagic)))                 // 沒有 KNLT
        XCTAssertThrowsError(try TelinkOTA.validate(Data(img.prefix(1000))))        // 長度不合法

        // 封包格式
        let data = Data((0..<20).map { UInt8($0) })
        XCTAssertEqual(TelinkOTA.packetCount(data), 2)
        let p1 = [UInt8](TelinkOTA.packet(data, index: 1))
        XCTAssertEqual(p1.count, 20)
        XCTAssertEqual(Array(p1[0..<6]), [1, 0, 16, 17, 18, 19])
        XCTAssertEqual(Array(p1[6..<18]), [UInt8](repeating: 0xFF, count: 12))      // 不足補 FF
        let c = TelinkOTA.crc16(p1, length: 18)
        XCTAssertEqual(p1[18], UInt8(c & 0xFF)); XCTAssertEqual(p1[19], UInt8(c >> 8))

        // 結束包:idx=255 → ~idx(16 位)=0xFF00
        XCTAssertEqual(Array([UInt8](TelinkOTA.endPacket(lastIndex: 255)).prefix(6)), [0x02, 0xFF, 0xFF, 0x00, 0x00, 0xFF])
        XCTAssertEqual(TelinkOTA.startCommand, Data([0x00, 0xFF]))

        let frames = TelinkOTA.frames(for: Data(img))
        XCTAssertEqual(frames.count, 65 + 2)                                         // 開始 + 65 包資料 + 結束
        XCTAssertEqual(frames.first, Data([0x00, 0xFF]))
        XCTAssertEqual(frames.last, TelinkOTA.endPacket(lastIndex: 64))
    }

    func testFirmwareCatalog() {
        XCTAssertEqual(FirmwareCatalog.known.count, 6)
        XCTAssertTrue(FirmwareCatalog.known.allSatisfy { $0.sha256.count == 64 && $0.sha256 == $0.sha256.lowercased() })
        XCTAssertEqual(Set(FirmwareCatalog.known.map(\.sha256)).count, 6)              // 沒有重複
        let official = FirmwareCatalog.identify(sha256: "7F7219630F7CA86D4D72ABC5FD99E530655EAE86BF05CA5E4407F25FD36B3148")
        XCTAssertEqual(official?.version, "V8.4.7"); XCTAssertEqual(official?.kind, .official)
        XCTAssertEqual(FirmwareCatalog.known.filter { $0.kind == .overclock }.count, 4)
        XCTAssertNil(FirmwareCatalog.identify(sha256: String(repeating: "0", count: 64)))
        // 所有已知韌體的大小都符合 Telink 映像檔規則
        XCTAssertTrue(FirmwareCatalog.known.allSatisfy { $0.size >= 1024 && $0.size < TelinkOTA.maxSize && $0.size % 16 == 4 })
    }
}
