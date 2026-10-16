import Foundation

struct ReleaseInfo: Equatable {
    let build: Int
    let title: String
    let notes: String
    let pageURL: URL
    let ipaURL: URL?
}

/// 更新提示:側載 App 沒有商店通知,改查 GitHub Releases(每次 CI 編譯成功自動發佈,tag 為 build-<編號>)。
/// 以 CFBundleVersion(= CI 的 run number)比較新舊。
@MainActor
final class UpdateChecker: ObservableObject {
    enum State: Equatable { case idle, checking, upToDate, available(ReleaseInfo), failed(String) }

    @Published private(set) var state: State = .idle
    @Published var dismissedBuild: Int

    static let repo = "engnyg/redmagic-ice"
    private static let lastCheckKey = "update.lastCheck"
    private static let dismissedKey = "update.dismissedBuild"

    var currentBuild: Int { Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "") ?? 0 }

    /// 有新版本且尚未被使用者關閉提示
    var banner: ReleaseInfo? {
        if case .available(let r) = state, r.build != dismissedBuild { return r }
        return nil
    }

    init() { dismissedBuild = UserDefaults.standard.integer(forKey: Self.dismissedKey) }

    func dismissBanner() {
        if case .available(let r) = state {
            dismissedBuild = r.build
            UserDefaults.standard.set(r.build, forKey: Self.dismissedKey)
        }
    }

    /// 啟動時自動檢查(6 小時內檢查過就略過);手動檢查傳 force: true。
    func check(force: Bool = false) async {
        let d = UserDefaults.standard
        if !force, Date().timeIntervalSince1970 - d.double(forKey: Self.lastCheckKey) < 6 * 3600 { return }
        state = .checking
        do {
            var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!)
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            req.timeoutInterval = 15
            let (data, resp) = try await URLSession.shared.data(for: req)
            d.set(Date().timeIntervalSince1970, forKey: Self.lastCheckKey)
            guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            if http.statusCode == 404 { state = .upToDate; return }          // 尚無任何發佈
            guard http.statusCode == 200 else { throw URLError(.badServerResponse) }
            let r = try JSONDecoder().decode(GHRelease.self, from: data)
            guard let build = Int(r.tag_name.replacingOccurrences(of: "build-", with: "")) else { state = .upToDate; return }
            if build > currentBuild, let page = URL(string: r.html_url) {
                let ipa = r.assets.first { $0.name.hasSuffix(".ipa") }.flatMap { URL(string: $0.browser_download_url) }
                state = .available(ReleaseInfo(build: build, title: r.name ?? r.tag_name, notes: r.body ?? "", pageURL: page, ipaURL: ipa))
            } else {
                state = .upToDate
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private struct GHRelease: Decodable {
        struct Asset: Decodable { let name: String; let browser_download_url: String }
        let tag_name: String
        let name: String?
        let body: String?
        let html_url: String
        let assets: [Asset]
    }
}
