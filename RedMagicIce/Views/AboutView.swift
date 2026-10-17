import SwiftUI

struct AboutView: View {
    @EnvironmentObject var ble: CoolerBLEManager
    @EnvironmentObject var updates: UpdateChecker
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    static let projectURL = URL(string: "https://github.com/\(UpdateChecker.repo)")!

    private var version: String {
        let i = Bundle.main.infoDictionary
        let v = i?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = i?["CFBundleVersion"] as? String ?? "1"
        return "\(v)(\(b))"
    }

    var body: some View {
        ZStack {
            AppBackground(accent: .indigo)
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 10) {
                        Image("Logo").resizable().scaledToFit().frame(width: 120, height: 120)
                            .shadow(color: .cyan.opacity(0.4), radius: 18)
                        Text("極凍").font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(.white)
                        Text("CRYO · 紅魔散熱器控制").font(.caption.weight(.semibold)).tracking(2).foregroundStyle(.white.opacity(0.6))
                        Text("版本 \(version)").font(.footnote.monospacedDigit()).foregroundStyle(.white.opacity(0.75))
                    }
                    .frame(maxWidth: .infinity).padding(.top, 8)

                    card("更新") { updateSection }

                    card("簡介") {
                        Text("用藍牙直接控制紅魔磁吸散熱背夾:散熱開關、1~10 檔手動檔位、智慧溫控、破壞神,以及三種自動溫控(自由變頻、電池溫控、目標溫度)。支援燈光、動態燈效、動態島即時動態與自訂背景。")
                    }

                    card("開源專案") {
                        Text("原始碼、更新紀錄與問題回報都在 GitHub。")
                        Text(Self.projectURL.absoluteString).font(.caption.monospaced()).foregroundStyle(.cyan)
                        GlassGroup {
                            FlowRow {
                                GlassChip(title: "開啟 GitHub 專案", symbol: "chevron.left.forwardslash.chevron.right", selected: true, tint: .indigo) {
                                    openURL(Self.projectURL)
                                }
                                GlassChip(title: "所有版本", symbol: "tag") { openURL(Self.projectURL.appendingPathComponent("releases")) }
                                GlassChip(title: "回報問題", symbol: "exclamationmark.bubble") { openURL(Self.projectURL.appendingPathComponent("issues")) }
                            }
                        }
                    }

                    card("目前裝置") {
                        row("機型", ble.connected ? ble.modelTitle : "未連線")
                        row("韌體", ble.connected && !ble.firmware.isEmpty ? ble.firmware : "--")
                    }

                    card("安全提醒") {
                        Text("散熱器製冷面可能降到 0°C 以下,手機背面可能凝露。請從低檔位開始,留意溫度與轉速,不要在無人看管時長時間使用高檔位、破壞神或實驗性的超頻探測。")
                    }

                    card("聲明") {
                        Text("本 App 為第三方獨立製作,與努比亞(Nubia)及紅魔(RedMagic)無任何關聯,亦非官方產品。使用本 App 控制硬體的風險由使用者自行承擔。")
                    }

                    GlassChip(title: "關閉", symbol: "xmark") { dismiss() }
                }
                .padding(16)
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private var updateSection: some View {
        switch updates.state {
        case .idle: Text("尚未檢查更新。")
        case .checking: HStack { ProgressView(); Text("檢查中…") }
        case .upToDate: Label("已是最新版本(build \(updates.currentBuild))", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed(let e): Label("檢查失敗:\(e)", systemImage: "wifi.exclamationmark").foregroundStyle(.orange)
        case .available(let r):
            VStack(alignment: .leading, spacing: 8) {
                Label("有新版本 build \(r.build)(目前 build \(updates.currentBuild))", systemImage: "arrow.down.circle.fill").foregroundStyle(.cyan)
                if !r.notes.isEmpty { Text(r.notes).font(.caption).foregroundStyle(.white.opacity(0.75)) }
                GlassGroup {
                    FlowRow {
                        GlassChip(title: "查看並下載", symbol: "safari", selected: true, tint: .cyan) { openURL(r.pageURL) }
                        if let ipa = r.ipaURL,
                           let alt = URL(string: "altstore://install?url=" + (ipa.absoluteString.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")) {
                            GlassChip(title: "用 AltStore 開啟", symbol: "square.and.arrow.down") { openURL(alt) }
                        }
                    }
                }
            }
        }
        GlassChip(title: "檢查更新", symbol: "arrow.clockwise") { Task { await updates.check(force: true) } }
    }

    private func card<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content().font(.footnote).foregroundStyle(.white.opacity(0.8)).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.white).glassCard()
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack { Text(k); Spacer(); Text(v).foregroundStyle(.white.opacity(0.7)) }
    }
}
