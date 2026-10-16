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
        let c = TempCurve.freeDefault
        XCTAssertEqual(c.level(at: -20), 1)
        XCTAssertEqual(c.level(at: 40), 10)
        XCTAssertEqual(c.level(at: 2.5), 2.5, accuracy: 0.001)
        XCTAssertEqual(AutoLogic.curveIndex(curve: c, temp: 25, current: nil), 9)
        // 遲滯:目標 3.4 檔,目前 3 檔(差 0.4 < 0.55)保持不動
        XCTAssertEqual(AutoLogic.curveIndex(curve: c, temp: 7, current: 2), 2)
        XCTAssertEqual(AutoLogic.curveIndex(curve: .batteryDefault, temp: 50, current: nil), 9)
        XCTAssertEqual(AutoLogic.curveIndex(curve: .batteryDefault, temp: 30, current: nil), 0)
    }

    func testTargetControl() {
        XCTAssertEqual(AutoLogic.targetBaseIndex(diff: -3), 0)
        XCTAssertEqual(AutoLogic.targetBaseIndex(diff: 1.5), 1)
        XCTAssertEqual(AutoLogic.targetBaseIndex(diff: 5), 4)
        XCTAssertEqual(AutoLogic.targetBaseIndex(diff: 12), 9)
        XCTAssertEqual(AutoLogic.targetIndex(cooler: 24, target: 18, current: nil), 4)
        // 升檔立即,降檔需多降 0.7℃
        XCTAssertEqual(AutoLogic.targetIndex(cooler: 20.4, target: 18, current: 2), 2)   // diff 2.4:base=2,持平
        XCTAssertEqual(AutoLogic.targetIndex(cooler: 19.5, target: 18, current: 2), 2)   // diff 1.5:base=1,但 down(2.2)=2,遲滯內保持
        XCTAssertEqual(AutoLogic.targetIndex(cooler: 18.2, target: 18, current: 2), 0)   // diff 0.2:降到 0
        XCTAssertEqual(AutoLogic.targetIndex(cooler: 26, target: 18, current: 2), 6)     // diff 8:立即升檔
    }
}
