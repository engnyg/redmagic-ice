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
