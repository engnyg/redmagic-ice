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
}
