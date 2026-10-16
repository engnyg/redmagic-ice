# 極凍 Cryo — 紅魔散熱器 iOS 控制 App

<img src="RedMagicIce/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="120" alt="極凍 Cryo 圖示">

SwiftUI + CoreBluetooth 製作的紅魔散熱器 iOS 控制 App。

## 功能
- 掃描/連線紅魔散熱器、自動重連上次裝置
- 散熱開關、10 檔手動檔位、智慧溫控、破壞神
- 燈光(炫彩 / 多色呼吸 / 單色呼吸 / 常亮 / 關燈 + 15 個預設色)
- 即時溫度、轉速、功率、韌體版本、通訊日誌
- 動態島 / 鎖屏即時動態(Live Activity):緊湊態顯示溫度,展開顯示模式、轉速、功率;連線後自動開啟,「更多」裡可關閉
- App 驅動的動態燈效、溫度/檔位/模式聯動燈光、自定義背景(純色/漸變/相簿照片)

## 構建(需 macOS + Xcode 15+)
```
brew install xcodegen
xcodegen generate
open RedMagicIce.xcodeproj
```
在 Signing 中選擇你自己的 Team,把 `PRODUCT_BUNDLE_IDENTIFIER` 改成唯一值,真機執行(模擬器無藍牙)。

> ⚠️ 本倉庫程式碼在 Linux 環境編寫,**尚未編譯/真機測試**;協議來自靜態分析,首次連線請從日誌面板觀察 TX/回包是否符合預期。
