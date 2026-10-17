import XCTest
@testable import RedMagicIce

final class AppearanceTests: XCTestCase {
    func testOldSettingsJSONStillDecodes() throws {
        // build 31 以前的存檔沒有 photoScale / photoX / photoY / videoFile,不能因此被重置
        let json = #"{"style":"photo","color1":{"r":1,"g":2,"b":3},"color2":{"r":4,"g":5,"b":6},"blur":7,"dim":0.4}"#
        let s = try JSONDecoder().decode(AppearanceSettings.self, from: Data(json.utf8))
        XCTAssertEqual(s.style, .photo)
        XCTAssertEqual(s.blur, 7)
        XCTAssertEqual(s.dim, 0.4, accuracy: 1e-9)
        XCTAssertEqual(s.photoScale, 1)
        XCTAssertEqual(s.photoX, 0)
        XCTAssertNil(s.videoFile)
    }

    func testUnknownStyleFallsBackToAurora() throws {
        let json = #"{"style":"hologram"}"#
        let s = try JSONDecoder().decode(AppearanceSettings.self, from: Data(json.utf8))
        XCTAssertEqual(s.style, .aurora)
    }

    func testSettingsRoundTrip() throws {
        var s = AppearanceSettings()
        s.style = .video; s.videoFile = "v.mp4"; s.photoScale = 2.5; s.photoX = -0.3; s.photoY = 0.8
        let back = try JSONDecoder().decode(AppearanceSettings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back, s)
    }

    func testPhotoLayoutFillsContainer() {
        // 1000x500 的橫圖放進 400x800 的直立畫面:高度先填滿,寬度有可移動範圍
        let r = PhotoLayout.frame(image: CGSize(width: 1000, height: 500), container: CGSize(width: 400, height: 800),
                                  scale: 1, x: 0, y: 0)
        XCTAssertEqual(r.size.height, 800, accuracy: 0.01)
        XCTAssertEqual(r.size.width, 1600, accuracy: 0.01)
        XCTAssertEqual(r.maxOffset.width, 600, accuracy: 0.01)
        XCTAssertEqual(r.maxOffset.height, 0, accuracy: 0.01)
        XCTAssertEqual(r.offset, .zero)
    }

    func testPhotoLayoutClampsOffset() {
        let r = PhotoLayout.frame(image: CGSize(width: 1000, height: 500), container: CGSize(width: 400, height: 800),
                                  scale: 1, x: 5, y: -5, drag: CGSize(width: 10_000, height: 10_000))
        XCTAssertEqual(r.offset.width, 600, accuracy: 0.01)
        XCTAssertEqual(r.offset.height, 0, accuracy: 0.01)
    }

    func testPhotoLayoutScaleAndNormalize() {
        let c = CGSize(width: 400, height: 800)
        let img = CGSize(width: 400, height: 800)
        let r = PhotoLayout.frame(image: img, container: c, scale: 2, x: 0, y: 0, drag: CGSize(width: 100, height: -200))
        XCTAssertEqual(r.size.width, 800, accuracy: 0.01)
        XCTAssertEqual(r.maxOffset.width, 200, accuracy: 0.01)
        XCTAssertEqual(r.maxOffset.height, 400, accuracy: 0.01)
        let n = PhotoLayout.normalized(r.offset, maxOffset: r.maxOffset)
        XCTAssertEqual(n.x, 0.5, accuracy: 1e-9)
        XCTAssertEqual(n.y, -0.5, accuracy: 1e-9)
        // 縮放上限 5、下限 1
        XCTAssertEqual(PhotoLayout.frame(image: img, container: c, scale: 99, x: 0, y: 0).size.width, 2000, accuracy: 0.01)
        XCTAssertEqual(PhotoLayout.frame(image: img, container: c, scale: 0.1, x: 0, y: 0).size.width, 400, accuracy: 0.01)
    }
}

final class CoolerNameTests: XCTestCase {
    func testModelDetectionFromNames() {
        XCTAssertEqual(CoolerModel.detect(name: "RM Magcooler 8pro"), .rm8Pro)
        XCTAssertEqual(CoolerModel.detect(name: "SRQ_8PRO_BLE_F80"), .rm8Pro)
        XCTAssertEqual(CoolerModel.detect(name: ""), .unknown)
        XCTAssertEqual(CoolerModel.detect(name: "紅魔散熱器"), .unknown)
    }
}

final class EffectSimulatorTests: XCTestCase {
    private let two = [RGB(r: 255, g: 0, b: 0), RGB(r: 0, g: 0, b: 255)]

    func testAllEffectsProduceSixteenPixels() {
        for e in 1...8 {
            for t in stride(from: 0.0, to: 5.0, by: 0.37) {
                XCTAssertEqual(FirmwareEffectSimulator.frame(effect: e, palette: two, speed: 50, brightness: 100, time: t).count, 16)
            }
        }
    }

    func testPulseIsAllOnThenAllOff() {
        // 效果 1:亮相位開頭整圈同色,之後全暗
        let on = FirmwareEffectSimulator.frame(effect: 1, palette: two, speed: 50, brightness: 100, time: 0)
        XCTAssertEqual(Set(on.map { $0 }).count, 1)
        XCTAssertNotEqual(on[0], .black)
        let period = Double(FirmwareLight.period(speed: 50, effect: 1))
        let off = FirmwareEffectSimulator.frame(effect: 1, palette: two, speed: 50, brightness: 100,
                                                time: (period / 3 + 1) * FirmwareEffectSimulator.tick)
        XCTAssertTrue(off.allSatisfy { $0 == .black })
    }

    func testFillEffectGrowsFromPixelZero() {
        let stepDur = Double(FirmwareLight.period(speed: 50, effect: 7)) * FirmwareEffectSimulator.tick
        let f = FirmwareEffectSimulator.frame(effect: 7, palette: two, speed: 50, brightness: 100, time: stepDur * 3.5)
        XCTAssertEqual(f.prefix(4).filter { $0 != .black }.count, 4)     // 0...3 亮
        XCTAssertTrue(f.suffix(12).allSatisfy { $0 == .black })
    }

    func testBrightnessScalesColors() {
        let full = FirmwareEffectSimulator.frame(effect: 3, palette: two, speed: 50, brightness: 100, time: 0)[0]
        let half = FirmwareEffectSimulator.frame(effect: 3, palette: two, speed: 50, brightness: 50, time: 0)[0]
        XCTAssertGreaterThan(full.r, half.r)
    }

    func testEmptyPaletteIsDark() {
        XCTAssertTrue(FirmwareEffectSimulator.frame(effect: 2, palette: [], speed: 50, brightness: 100, time: 1).allSatisfy { $0 == .black })
    }
}

final class HSVTests: XCTestCase {
    func testHSVRoundTrip() {
        for c in [RGB(r: 255, g: 0, b: 0), RGB(r: 0, g: 255, b: 0), RGB(r: 0, g: 0, b: 255), RGB(r: 255, g: 255, b: 0),
                  RGB(r: 12, g: 200, b: 99), RGB(r: 255, g: 255, b: 255), RGB(r: 90, g: 90, b: 90)] {
            let x = c.hsv
            let back = RGB.hsv(x.h, x.s, x.v)
            XCTAssertEqual(Int(back.r), Int(c.r), accuracy: 1)
            XCTAssertEqual(Int(back.g), Int(c.g), accuracy: 1)
            XCTAssertEqual(Int(back.b), Int(c.b), accuracy: 1)
        }
    }

    func testHSVKnownValues() {
        let red = RGB(r: 255, g: 0, b: 0).hsv
        XCTAssertEqual(red.h, 0, accuracy: 0.01); XCTAssertEqual(red.s, 1, accuracy: 1e-9); XCTAssertEqual(red.v, 1, accuracy: 1e-9)
        XCTAssertEqual(RGB(r: 0, g: 255, b: 0).hsv.h, 120, accuracy: 0.01)
        XCTAssertEqual(RGB(r: 0, g: 0, b: 255).hsv.h, 240, accuracy: 0.01)
        XCTAssertEqual(RGB.black.hsv.v, 0)
        XCTAssertEqual(RGB.white.hsv.s, 0)
    }
}
