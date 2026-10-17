import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 韌體刷寫(Telink OTA)。高風險功能:不內建任何韌體檔,只刷你自己選擇、且通過驗證的 .bin。
struct FirmwareFlashView: View {
    @EnvironmentObject var ble: CoolerBLEManager
    @EnvironmentObject var ota: TelinkOTAController
    @EnvironmentObject var light: LightController
    @EnvironmentObject var auto: AutoController

    static let confirmPhrase = "刷韌體導致的問題由我自行承擔"

    @State private var picking = false
    @State private var fileName = ""
    @State private var image: Data?
    @State private var imageError: String?
    @State private var typed = ""
    @State private var showTrace = false

    private var sha: String { image.map(TelinkOTA.sha256Hex) ?? "" }
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
    private var confirmed: Bool { typed.trimmingCharacters(in: .whitespaces) == Self.confirmPhrase }

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
        imageError = nil; image = nil; typed = ""
        guard case .success(let urls) = r, let url = urls.first else { imageError = "沒有選到檔案"; return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size <= TelinkOTA.maxSize else {
            imageError = "檔案過大,不是本設備支援的 Telink BIN"; return
        }
        guard let d = try? Data(contentsOf: url) else { imageError = "無法讀取所選檔案"; return }
        fileName = url.lastPathComponent
        do { try TelinkOTA.validate(d); image = d } catch { image = d; imageError = error.localizedDescription }
    }
}
