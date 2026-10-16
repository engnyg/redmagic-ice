import SwiftUI
import UIKit

struct AppearanceSettings: Codable, Equatable {
    enum Style: String, Codable, CaseIterable, Identifiable {
        case aurora, solid, gradient, photo
        var id: String { rawValue }
        var title: String {
            switch self {
            case .aurora: return "極光"
            case .solid: return "純色"
            case .gradient: return "漸變"
            case .photo: return "照片"
            }
        }
        var symbol: String {
            switch self {
            case .aurora: return "sparkles"
            case .solid: return "circle.fill"
            case .gradient: return "circle.lefthalf.filled"
            case .photo: return "photo"
            }
        }
    }
    var style: Style = .aurora
    var color1 = RGB(r: 10, g: 12, b: 30)
    var color2 = RGB(r: 70, g: 40, b: 140)
    var blur: Double = 0      // 照片模糊(0...30)
    var dim: Double = 0.25    // 壓暗(0...0.7),保證白色文字可讀
}

/// 自定義背景:極光(隨模式變色) / 純色 / 漸變 / 相簿照片。
final class AppearanceController: ObservableObject {
    @Published var settings: AppearanceSettings { didSet { save() } }
    @Published private(set) var photo: UIImage?
    @Published var message: String?

    private static let key = "appearance.v1"
    private static var photoURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("background.jpg")
    }

    init() {
        if let d = UserDefaults.standard.data(forKey: Self.key),
           let s = try? JSONDecoder().decode(AppearanceSettings.self, from: d) {
            settings = s
        } else {
            settings = AppearanceSettings()
        }
        photo = UIImage(contentsOfFile: Self.photoURL.path)
    }

    /// 縮放到長邊 ≤1600 後儲存,避免佔用過多記憶體/空間。
    func setPhoto(data: Data) {
        guard let img = UIImage(data: data) else { message = "無法解析這張照片"; return }
        let scale = min(1, 1600 / max(img.size.width, img.size.height))
        let size = CGSize(width: img.size.width * scale, height: img.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1     // 以像素為單位縮放,避免 3x 螢幕倍率讓圖片變成 4800px
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            img.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let jpg = resized.jpegData(compressionQuality: 0.85) else { message = "照片編碼失敗"; return }
        do { try jpg.write(to: Self.photoURL, options: .atomic) } catch { message = "儲存失敗:\(error.localizedDescription)"; return }
        photo = resized
        settings.style = .photo
        message = "已套用照片"
    }

    func removePhoto() {
        try? FileManager.default.removeItem(at: Self.photoURL)
        photo = nil
        if settings.style == .photo { settings.style = .aurora }
    }

    private func save() {
        if let d = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(d, forKey: Self.key) }
    }
}

struct AppBackground: View {
    @EnvironmentObject var appearance: AppearanceController
    var accent: Color

    var body: some View {
        let s = appearance.settings
        ZStack {
            switch s.style {
            case .aurora:
                AuroraBackground(accent: accent)
            case .solid:
                s.color1.color
            case .gradient:
                LinearGradient(colors: [s.color1.color, s.color2.color], startPoint: .topLeading, endPoint: .bottomTrailing)
            case .photo:
                if let img = appearance.photo {
                    Color.clear.overlay(
                        Image(uiImage: img).resizable().scaledToFill().blur(radius: s.blur)
                    ).clipped()
                } else {
                    AuroraBackground(accent: accent)
                }
            }
            if s.style != .aurora { Color.black.opacity(s.dim) }
        }
        .ignoresSafeArea()
    }
}
