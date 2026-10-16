import XCTest
@testable import RedMagicIce

final class CoolerProtocolTests: XCTestCase {
    func testCommands() {
        XCTAssertEqual(CoolerProtocol.powerOn, Data([2]))
        XCTAssertEqual(CoolerProtocol.powerOff, Data([3]))
        XCTAssertEqual(CoolerProtocol.fanLevel(index: 0), Data([40]))
        XCTAssertEqual(CoolerProtocol.fanLevel(index: 99), Data([80]))
        XCTAssertEqual(CoolerProtocol.lightPayload(.solid(rgb: (1, 2, 3))), Data([4, 1, 2, 3]))
        XCTAssertEqual(CoolerProtocol.lightPayload(.off), Data([5, 0, 0, 0]))
        XCTAssertEqual(CoolerProtocol.lightPayload(.batteryTemp), Data([6, 0, 0, 0]))
    }

    func testStatusPackets() {
        XCTAssertEqual(CoolerProtocol.parseStatus(Data([4, 25])).temperatureC, 25)
        XCTAssertEqual(CoolerProtocol.parseStatus(Data([8, 0x0B, 0xB8])).rpm, 3000)
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
        XCTAssertEqual(LightFrames.tempBandColor(30), RGB(r: 55, g: 200, b: 187))
        XCTAssertEqual(LightFrames.tempBandColor(50), red)
        XCTAssertEqual(LightFrames.levelColor(level: 9, count: 10), red)
        XCTAssertEqual(RGB.white.scaled(0.5), RGB(r: 128, g: 128, b: 128))
    }
}
