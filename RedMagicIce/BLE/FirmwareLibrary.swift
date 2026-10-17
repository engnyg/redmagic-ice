import Foundation

/// 韌體庫:匯入一次、之後可重複選用。檔案保存在 App 沙盒內,每次取用都重新比對 SHA-256,
/// 發現檔案被改動或損壞就丟棄,不會把壞檔送去刷寫。
final class FirmwareLibrary: ObservableObject {
    struct Item: Identifiable, Codable, Equatable {
        let sha256: String
        var fileName: String
        let size: Int
        let addedAt: Date
        var id: String { sha256 }
        var known: KnownFirmware? { FirmwareCatalog.identify(sha256: sha256) }
    }

    @Published private(set) var items: [Item] = []

    private let dir: URL
    private var indexURL: URL { dir.appendingPathComponent("index.json") }

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        dir = base.appendingPathComponent("firmware_library", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let d = try? Data(contentsOf: indexURL), let list = try? JSONDecoder().decode([Item].self, from: d) {
            items = list.filter { FileManager.default.fileExists(atPath: file(for: $0.sha256).path) }
        }
    }

    private func file(for sha: String) -> URL { dir.appendingPathComponent("\(sha).bin") }

    private func saveIndex() {
        if let d = try? JSONEncoder().encode(items) { try? d.write(to: indexURL, options: .atomic) }
    }

    /// 驗證通過才保存;相同 SHA-256 只保留一份
    @discardableResult
    func add(data: Data, fileName: String) throws -> Item {
        try TelinkOTA.validate(data)
        let sha = TelinkOTA.sha256Hex(data)
        if let existing = items.first(where: { $0.sha256 == sha }) { return existing }
        try data.write(to: file(for: sha), options: .atomic)
        let item = Item(sha256: sha, fileName: fileName, size: data.count, addedAt: Date())
        items.append(item)
        saveIndex()
        return item
    }

    /// 取用時再次驗證:SHA-256 必須與記錄一致,且通過 Telink 映像檔驗證
    func load(_ item: Item) -> Data? {
        guard let d = try? Data(contentsOf: file(for: item.sha256)),
              TelinkOTA.sha256Hex(d) == item.sha256,
              (try? TelinkOTA.validate(d)) != nil else {
            remove(item)
            return nil
        }
        return d
    }

    func remove(_ item: Item) {
        try? FileManager.default.removeItem(at: file(for: item.sha256))
        items.removeAll { $0.sha256 == item.sha256 }
        saveIndex()
    }
}
