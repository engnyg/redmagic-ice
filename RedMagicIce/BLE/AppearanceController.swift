import SwiftUI
import UIKit
import AVFoundation
import CoreTransferable
import UniformTypeIdentifiers

struct AppearanceSettings: Codable, Equatable {
    enum Style: String, Codable, CaseIterable, Identifiable {
        case aurora, solid, gradient, photo, video
        var id: String { rawValue }
        var title: String {
            switch self {
            case .aurora: return "極光"
            case .solid: return "純色"
            case .gradient: return "漸變"
            case .photo: return "照片"
            case .video: return "影片"
            }
        }
        var symbol: String {
            switch self {
            case .aurora: return "sparkles"
            case .solid: return "circle.fill"
            case .gradient: return "circle.lefthalf.filled"
            case .photo: return "photo"
            case .video: return "play.rectangle"
            }
        }
    }
    var style: Style = .aurora
    var color1 = RGB(r: 10, g: 12, b: 30)
    var color2 = RGB(r: 70, g: 40, b: 140)
    var blur: Double = 0      // 照片模糊(0...30)
    var dim: Double = 0.25    // 壓暗(0...0.7),保證白色文字可讀
    var photoScale: Double = 1   // 照片縮放(1...5,1 = 剛好填滿)
    var photoX: Double = 0       // 照片位置,-1...1(相對於可移動範圍)
    var photoY: Double = 0
    var videoFile: String?       // Application Support 內的影片檔名

    init() {}

    // 舊版存檔沒有新欄位:全部用 decodeIfPresent,避免解碼失敗而重置設定。
    private enum CodingKeys: String, CodingKey {
        case style, color1, color2, blur, dim, photoScale, photoX, photoY, videoFile
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        style = (try? c.decodeIfPresent(Style.self, forKey: .style)) ?? .aurora
        color1 = try c.decodeIfPresent(RGB.self, forKey: .color1) ?? color1
        color2 = try c.decodeIfPresent(RGB.self, forKey: .color2) ?? color2
        blur = try c.decodeIfPresent(Double.self, forKey: .blur) ?? blur
        dim = try c.decodeIfPresent(Double.self, forKey: .dim) ?? dim
        photoScale = try c.decodeIfPresent(Double.self, forKey: .photoScale) ?? 1
        photoX = try c.decodeIfPresent(Double.self, forKey: .photoX) ?? 0
        photoY = try c.decodeIfPresent(Double.self, forKey: .photoY) ?? 0
        videoFile = try c.decodeIfPresent(String.self, forKey: .videoFile)
    }
}

/// 照片的縮放 / 位置換算:背景與調整畫面共用同一套,所見即所得。
enum PhotoLayout {
    struct Result: Equatable { var size: CGSize; var offset: CGSize; var maxOffset: CGSize }

    /// scale ≥ 1;x、y 為 -1...1 的位置;drag 為進行中的拖曳(點)。結果的 offset 一定落在可移動範圍內。
    static func frame(image: CGSize, container: CGSize, scale: Double, x: Double, y: Double,
                      drag: CGSize = .zero) -> Result {
        guard image.width > 0, image.height > 0, container.width > 0, container.height > 0 else {
            return Result(size: container, offset: .zero, maxOffset: .zero)
        }
        let base = max(container.width / image.width, container.height / image.height)
        let s = base * CGFloat(min(max(scale, 1), 5))
        let size = CGSize(width: image.width * s, height: image.height * s)
        let maxX = max(0, (size.width - container.width) / 2)
        let maxY = max(0, (size.height - container.height) / 2)
        let ox = min(max(CGFloat(min(max(x, -1), 1)) * maxX + drag.width, -maxX), maxX)
        let oy = min(max(CGFloat(min(max(y, -1), 1)) * maxY + drag.height, -maxY), maxY)
        return Result(size: size, offset: CGSize(width: ox, height: oy), maxOffset: CGSize(width: maxX, height: maxY))
    }

    /// 把點為單位的偏移換回 -1...1。
    static func normalized(_ offset: CGSize, maxOffset: CGSize) -> (x: Double, y: Double) {
        (maxOffset.width > 0 ? Double(offset.width / maxOffset.width) : 0,
         maxOffset.height > 0 ? Double(offset.height / maxOffset.height) : 0)
    }
}

/// 自定義背景:極光(隨模式變色) / 純色 / 漸變 / 相簿照片 / 循環影片。
final class AppearanceController: ObservableObject {
    @Published var settings: AppearanceSettings { didSet { save(); refreshPlayer() } }
    @Published private(set) var photo: UIImage?
    @Published private(set) var player: AVQueuePlayer?
    @Published var message: String?
    private var looper: AVPlayerLooper?

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
        // 靜音影片也不要打斷使用者正在播的音樂
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            self?.player?.pause()
        }
        NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            self?.player?.play()
        }
        refreshPlayer()
    }

    // MARK: 影片

    private static var supportDir: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    var videoURL: URL? {
        guard let name = settings.videoFile else { return nil }
        let u = Self.supportDir.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }
    var hasVideo: Bool { videoURL != nil }

    /// 把選到的影片(mp4 / mov / m4v)複製進沙盒,確認可播放後套用。
    @MainActor
    func setVideo(from source: URL) async {
        let ext = ["mp4", "mov", "m4v"].contains(source.pathExtension.lowercased()) ? source.pathExtension.lowercased() : "mp4"
        let name = "background-video-\(UUID().uuidString.prefix(8)).\(ext)"
        let dest = Self.supportDir.appendingPathComponent(name)
        do { try FileManager.default.copyItem(at: source, to: dest) }
        catch { message = "複製影片失敗:\(error.localizedDescription)"; return }
        let asset = AVURLAsset(url: dest)
        let playable = (try? await asset.load(.isPlayable)) ?? false
        let hasTrack = ((try? await asset.loadTracks(withMediaType: .video)) ?? []).isEmpty == false
        guard playable, hasTrack else {
            try? FileManager.default.removeItem(at: dest)
            message = "這個影片無法播放(可能是不支援的編碼)"
            return
        }
        if let old = videoURL { try? FileManager.default.removeItem(at: old) }
        settings.videoFile = name
        settings.style = .video
        message = "已套用影片(靜音、循環播放)"
    }

    func removeVideo() {
        if let u = videoURL { try? FileManager.default.removeItem(at: u) }
        settings.videoFile = nil
        if settings.style == .video { settings.style = .aurora }
    }

    /// 只在影片背景時才持有播放器,切換風格就釋放。
    private func refreshPlayer() {
        guard settings.style == .video, let url = videoURL else {
            if player != nil { player?.pause(); looper = nil; player = nil }
            return
        }
        if player == nil {
            let item = AVPlayerItem(url: url)
            let q = AVQueuePlayer()
            q.isMuted = true
            q.preventsDisplaySleepDuringVideoPlayback = false
            looper = AVPlayerLooper(player: q, templateItem: item)
            player = q
        }
        player?.play()
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
        settings.photoScale = 1; settings.photoX = 0; settings.photoY = 0
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
                    GeometryReader { geo in
                        let f = PhotoLayout.frame(image: img.size, container: geo.size,
                                                  scale: s.photoScale, x: s.photoX, y: s.photoY)
                        Image(uiImage: img).resizable()
                            .frame(width: f.size.width, height: f.size.height)
                            .blur(radius: s.blur)
                            .offset(f.offset)
                            .frame(width: geo.size.width, height: geo.size.height)
                    }
                    .clipped()
                } else {
                    AuroraBackground(accent: accent)
                }
            case .video:
                if let p = appearance.player {
                    VideoBackground(player: p)
                } else {
                    AuroraBackground(accent: accent)
                }
            }
            if s.style != .aurora { Color.black.opacity(s.dim) }
        }
        .ignoresSafeArea()
    }
}

final class PlayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

/// 三個分頁各畫一次背景,但共用同一個 AVPlayer,所以只解碼一份影片。
struct VideoBackground: UIViewRepresentable {
    let player: AVPlayer
    func makeUIView(context: Context) -> PlayerView {
        let v = PlayerView()
        v.playerLayer.videoGravity = .resizeAspectFill
        v.playerLayer.player = player
        v.isUserInteractionEnabled = false
        return v
    }
    func updateUIView(_ v: PlayerView, context: Context) {
        if v.playerLayer.player !== player { v.playerLayer.player = player }
    }
}

/// 相簿選到的影片:複製成 App 自己的暫存檔再交給 AppearanceController(選取器給的檔案離開回呼就會被清掉)。
struct PickedMovie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let dst = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).\(ext)")
            try FileManager.default.copyItem(at: received.file, to: dst)
            return PickedMovie(url: dst)
        }
    }
}
