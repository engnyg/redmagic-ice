import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 韌體刷寫(Telink OTA)。高風險功能:不內建任何韌體檔,只刷你自己選擇、且通過驗證的 .bin。
struct FirmwareFlashView: View {
    @EnvironmentObject var ble: CoolerBLEManager
    @EnvironmentObject var ota: TelinkOTAController
    @EnvironmentObject var light: LightController
    @EnvironmentObject var auto: AutoController
    @EnvironmentObject var library: FirmwareLibrary

    static let confirmPhrase = "刷韌體導致的問題由我自行承擔"

    @State private var picking = false
    @State private var fileName = ""
    @State private var image: Data?
    @State private var imageError: String?
    @State private var typed = ""
    @State private var showTrace = false
    @State private var saveToLibrary = true
    @State private var ackOverclock = false

    private var sha: String { image.map(TelinkOTA.sha256Hex) ?? "" }
    private var identified: KnownFirmware? { sha.isEmpty ? nil : FirmwareCatalog.identify(sha256: sha) }
    private var needsOverclockAck: Bool { identified?.kind == .overclock }
    private var is8Pro: Bool { CoolerModel.detect(name: ble.deviceName) == .rm8Pro }
    private var batteryOK: Bool {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let lv = UIDevice.current.batteryLevel, st = UIDevice.current.batteryState
        return st == .charging || st == .full || lv >= 0.4
    }
    private var batteryText: String {
        let lv = UIDevice.current.batteryLevel
        return lv < 0 ? "未知" : "\(Int(lv * 100))%" + (UIDevice.current.batteryState == .charging ? "(充電中)" : "")
    }
    private var checks: [(String, Bool, String)] {
        [("已連線散熱器", ble.connected, ble.connected ? ble.modelTitle : "未連線"),
         ("機型為紅魔 8 Pro", ble.connected && is8Pro, ble.connected ? ble.modelTitle : "--"),
         ("找到 Telink OTA 服務", ble.otaAvailable, ble.otaAvailable ? "已找到" : "未找到"),
         ("手機電量 ≥ 40% 或充電中", batteryOK, batteryText),
         ("韌體檔通過驗證", image != nil && imageError == nil, image == nil ? "尚未選擇" : (imageError ?? "KNLT 標識、長度、CRC32 皆正確"))]
    }
    private var allOK: Bool { checks.allSatisfy { $0.1 } }
    private var confirmed: Bool { typed.trimmingCharacters(in: .whitespaces) == Self.confirmPhrase && (!needsOverclockAck || ackOverclock) }

    var body: some View {
        ZStack {
            AppBackground(accent: .red)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    riskCard
                    if ota.phase == .idle { setupCards } else { progressCard }
                }
                .padding(16)
            }
        }
        .preferredColorScheme(.dark)
        .fileImporter(isPresented: $picking, allowedContentTypes: [.data], allowsMultipleSelection: false) { r in load(r) }
        .onChange(of: ota.phase) { p in UIApplication.shared.isIdleTimerDisabled = p.isRunning }   // 刷寫期間保持螢幕常亮
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    // MARK: 風險說明
    private var riskCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("韌體刷寫(高風險)", systemImage: "exclamationmark.triangle.fill").font(.headline).foregroundStyle(.yellow)
            Text("刷寫韌體不同於一般藍牙設定。刷錯機型或硬體批次、使用損壞或來源不明的 BIN、刷寫中途斷電、斷藍牙、離開或結束 App,都可能造成散熱器無法啟動、無法連線、燈光或風扇異常、進入恢復模式,甚至永久損壞。非官方或修改版韌體還可能影響保固與售後。")
                .font(.footnote).foregroundStyle(.white.opacity(0.85))
            Text("本 App 不內建任何韌體檔,也不保證任何韌體適用於所有 8 Pro 批次。刷之前請確認機型、供電穩定、電量充足;刷寫過程中不要關閉散熱器、拔電源、切換其他控制軟體或離開本畫面。因刷機、韌體本身、誤操作、設備個體差異、掉電或藍牙異常造成的損壞與後果,由使用者自行承擔。")
                .font(.footnote).foregroundStyle(.white.opacity(0.7))
        }
        .foregroundStyle(.white).glassCard(tint: .red)
    }

    // MARK: 選檔 / 檢查 / 確認
    @ViewBuilder private var setupCards: some View {
        libraryCard

        VStack(alignment: .leading, spacing: 10) {
            Text("1 · 選擇韌體檔").font(.headline)
            GlassChip(title: image == nil ? "從「檔案」選擇 .bin" : "重新選擇", symbol: "doc.badge.plus") { picking = true }
            if image != nil {
                VStack(alignment: .leading, spacing: 4) {
                    Text(fileName).font(.footnote.weight(.semibold)).lineLimit(2)
                    Text("\(image?.count ?? 0) 位元組 · \(TelinkOTA.packetCount(image ?? Data())) 包").font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.7))
                    Text("SHA-256 \(sha)").font(.system(size: 10, design: .monospaced)).foregroundStyle(.white.opacity(0.6)).textSelection(.enabled)
                }
            }
            if let e = imageError { Label(e, systemImage: "xmark.octagon.fill").font(.footnote).foregroundStyle(.red) }
            identityView
            if image != nil, imageError == nil {
                Toggle("保存到韌體庫(下次可直接選用)", isOn: $saveToLibrary)
            }
            Text("驗證規則與原作者相同:大小在 1 KB 與 124 KB 之間且 (大小 mod 16) = 4、偏移 8 處為 KNLT 標識、偏移 24 的長度欄位等於檔案大小、尾端 CRC32 正確。通過驗證只代表檔案完整,不代表適用於你的設備。")
                .font(.caption).foregroundStyle(.white.opacity(0.55))
        }
        .foregroundStyle(.white).glassCard()

        VStack(alignment: .leading, spacing: 8) {
            Text("2 · 刷前檢查").font(.headline)
            ForEach(Array(checks.enumerated()), id: \.offset) { _, c in
                HStack(alignment: .top) {
                    Image(systemName: c.1 ? "checkmark.circle.fill" : "xmark.circle.fill").foregroundStyle(c.1 ? .green : .red)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(c.0).font(.subheadline)
                        Text(c.2).font(.caption).foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
        }
        .foregroundStyle(.white).glassCard()

        VStack(alignment: .leading, spacing: 10) {
            Text("3 · 確認並開始").font(.headline)
            if needsOverclockAck {
                Toggle("我了解這是第三方修改的超頻韌體,會突破風扇出廠限制,可能損壞風扇或散熱器、影響保固", isOn: $ackOverclock)
                    .font(.footnote).tint(.red)
            }
            Text("請輸入以下句子以確認你了解風險:").font(.footnote).foregroundStyle(.white.opacity(0.7))
            Text(Self.confirmPhrase).font(.subheadline.weight(.semibold)).foregroundStyle(.yellow)
            TextField("在此輸入上面的句子", text: $typed)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .padding(12).glass(RoundedRectangle(cornerRadius: 16, style: .continuous))
            Toggle("相容節奏(每包間隔 12 毫秒,較慢但更穩)", isOn: $ota.compatibilityPacing)
            GlassChip(title: "開始刷寫", symbol: "bolt.fill", selected: allOK && confirmed, tint: .red) {
                guard allOK, confirmed, let img = image else { return }
                light.stop(); auto.stop()                               // 先停掉其他會寫入的功能
                ota.start(image: img)
            }
            .disabled(!(allOK && confirmed))
            if !allOK { Text("尚有檢查項目未通過,無法開始。").font(.caption).foregroundStyle(.orange) }
        }
        .foregroundStyle(.white).glassCard()
    }

    // MARK: 韌體庫與辨識
    @ViewBuilder private var identityView: some View {
        if let k = identified {
            VStack(alignment: .leading, spacing: 4) {
                Label("已辨識:\(k.title) \(k.version) · \(k.kindName)", systemImage: "checkmark.seal.fill")
                    .font(.footnote.weight(.semibold)).foregroundStyle(k.kind == .overclock ? .red : .green)
                Text(k.note).font(.caption).foregroundStyle(.white.opacity(0.7))
                if k.kind != .official {
                    Text("建議第一次先刷官方 V8.4.7,確認整個流程能跑通、刷完設備正常,再考慮其他韌體。")
                        .font(.caption).foregroundStyle(.yellow.opacity(0.85))
                }
            }
        } else if image != nil, imageError == nil {
            Label("未辨識的韌體:檔案完整,但不在已知清單內,請自行確認機型與來源", systemImage: "questionmark.diamond.fill")
                .font(.footnote).foregroundStyle(.orange)
        }
    }

    private var libraryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("韌體庫").font(.headline)
            Text("公開版 App 不含韌體檔(它們是努比亞與冰環作者的檔案,不能由本專案公開散佈)。個人版 IPA 可用 tools/inject_firmware.py 把韌體內建進去;也可以自己匯入一次,之後在這裡直接選用。所有檔案都會依 SHA-256 自動辨識版本與類型。")
                .font(.caption).foregroundStyle(.white.opacity(0.65))
            if library.items.isEmpty {
                Text("韌體庫是空的").font(.footnote).foregroundStyle(.white.opacity(0.5))
            }
            ForEach(library.items) { it in
                HStack(spacing: 10) {
                    Button { pick(it) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(it.known.map { "\($0.title) \($0.version)" } ?? it.fileName).font(.subheadline.weight(.semibold))
                            Text((it.isBuiltIn ? "內建 · " : "") + (it.known?.kindName ?? "未辨識") + " · \(it.size) 位元組 · " + it.sha256.prefix(8))
                                .font(.caption).foregroundStyle(kindColor(it.known?.kind))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain)
                    if !it.isBuiltIn {
                        Button { library.remove(it) } label: { Image(systemName: "trash").foregroundStyle(.white.opacity(0.6)) }.buttonStyle(.plain)
                    } else {
                        Image(systemName: "lock.fill").font(.footnote).foregroundStyle(.white.opacity(0.4))
                    }
                }
                .padding(10).glass(RoundedRectangle(cornerRadius: 16, style: .continuous), interactive: true)
            }
            let missing = FirmwareCatalog.known.filter { k in !library.items.contains { $0.sha256 == k.sha256 } }
            if !missing.isEmpty {
                Text("已知但尚未匯入").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.6)).padding(.top, 4)
                ForEach(missing) { k in
                    HStack {
                        Text("\(k.title) \(k.version)").font(.caption)
                        Spacer()
                        Text(k.kindName).font(.caption2).foregroundStyle(kindColor(k.kind))
                    }.foregroundStyle(.white.opacity(0.55))
                }
            }
        }
        .foregroundStyle(.white).glassCard()
    }

    private func kindColor(_ k: KnownFirmware.Kind?) -> Color {
        switch k { case .official: return .green; case .newLight: return .pink; case .overclock: return .red; case .none: return .gray }
    }

    private func pick(_ it: FirmwareLibrary.Item) {
        imageError = nil; typed = ""; ackOverclock = false
        guard let d = library.load(it) else { image = nil; imageError = "韌體庫中的檔案已損壞或被改動,已移除,請重新匯入"; return }
        image = d; fileName = it.fileName
    }

    // MARK: 進度 / 結果
    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            ProgressView(value: ota.progress).tint(tint)
            Text(ota.detail).font(.footnote).foregroundStyle(.white.opacity(0.85))
            if ota.phase.isRunning {
                Label("請保持本畫面開啟,不要離開、不要關閉散熱器或拔電源", systemImage: "lock.fill").font(.caption).foregroundStyle(.yellow)
                GlassChip(title: "中止", symbol: "stop.fill", selected: true, tint: .red) { ota.abort() }
            } else {
                GlassChip(title: "完成", symbol: "checkmark") { ota.reset() }
            }
            GlassChip(title: showTrace ? "隱藏記錄" : "顯示記錄", symbol: "doc.text") { showTrace.toggle() }
            if showTrace {
                ForEach(Array(ota.trace.suffix(60).enumerated()), id: \.offset) { _, l in
                    Text(l).font(.system(size: 10, design: .monospaced)).foregroundStyle(.white.opacity(0.7)).textSelection(.enabled)
                }
            }
        }
        .foregroundStyle(.white).glassCard(tint: tint)
    }

    private var title: String {
        switch ota.phase {
        case .preparing, .subscribing: return "準備中…"
        case .sending: return "刷寫中…"
        case .verifying: return "驗證與安裝中…"
        case .done: return "刷寫完成"
        case .unconfirmed: return "已送出,尚未確認"
        case .failed: return "刷寫未完成"
        case .idle: return ""
        }
    }
    private var tint: Color {
        switch ota.phase {
        case .done: return .green
        case .failed: return .red
        case .unconfirmed: return .orange
        default: return .blue
        }
    }

    private func load(_ r: Result<[URL], Error>) {
        imageError = nil; image = nil; typed = ""; ackOverclock = false
        guard case .success(let urls) = r, let url = urls.first else { imageError = "沒有選到檔案"; return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size <= TelinkOTA.maxSize else {
            imageError = "檔案過大,不是本設備支援的 Telink BIN"; return
        }
        guard let d = try? Data(contentsOf: url) else { imageError = "無法讀取所選檔案"; return }
        fileName = url.lastPathComponent
        do {
            try TelinkOTA.validate(d); image = d
            if saveToLibrary { try? library.add(data: d, fileName: fileName) }
        } catch { image = d; imageError = error.localizedDescription }
    }
}
