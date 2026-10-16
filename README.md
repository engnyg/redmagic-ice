# 冰環 iOS 版(紅魔散熱器控制器)

Android「冰環」(`com.magcooler.binghuan.v2646` v2.8.91)的 iOS 移植,SwiftUI + CoreBluetooth。
協議由 APK 反編譯得到,詳見 [docs/PROTOCOL.md](docs/PROTOCOL.md)。

## 已移植
- 掃描/連線紅魔散熱器、自動重連上次裝置
- 散熱開關、10 檔手動檔位、智慧溫控、破壞神
- 燈光(炫彩 / 呼吸 / 單色呼吸 / 常亮 / 關 / 電池溫度 + 15 個預設色)
- 即時溫度、轉速、功率、韌體版本、通訊日誌
- 動態島 / 鎖屏即時動態(Live Activity):緊湊態顯示溫度,展開顯示模式、轉速、功率;連線後自動開啟,「更多」裡可關閉
- App 驅動的動態燈效、溫度/檔位/模式聯動燈光、自定義背景(純色/漸變/相簿照片)

## 無法移植(iOS 無對應能力)
懸浮窗、通知欄/小米超級島(iOS 用動態島代替)、快捷設定磁貼、Shizuku、讀取手機電池/CPU 溫度做聯動、充電自動化、靜默安裝等。

## 構建(需 macOS + Xcode 15+)
```
brew install xcodegen
xcodegen generate
open RedMagicIce.xcodeproj
```
在 Signing 中選擇你自己的 Team,把 `PRODUCT_BUNDLE_IDENTIFIER` 改成唯一值,真機執行(模擬器無藍牙)。

> ⚠️ 本倉庫程式碼在 Linux 環境編寫,**尚未編譯/真機測試**;協議來自靜態分析,首次連線請從日誌面板觀察 TX/回包是否符合預期。
