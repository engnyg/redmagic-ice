# 冰环 iOS 版(红魔散热器控制器)

Android「冰环」(`com.magcooler.binghuan.v2646` v2.8.91)的 iOS 移植,SwiftUI + CoreBluetooth。
协议由 APK 反编译得到,详见 [docs/PROTOCOL.md](docs/PROTOCOL.md)。

## 已移植
- 扫描/连接红魔散热器、自动重连上次设备
- 散热开关、10 档手动档位、智能温控、破坏神
- 灯光(炫彩 / 呼吸 / 单色呼吸 / 常亮 / 关 / 电池温度 + 15 个预设色)
- 实时温度、转速、功率、固件版本、通信日志

## 无法移植(iOS 无对应能力)
悬浮窗、通知栏/小米超级岛、快捷设置磁贴、Shizuku、读取手机电池/CPU 温度做联动、充电自动化、静默安装等。

## 构建(需 macOS + Xcode 15+)
```
brew install xcodegen
xcodegen generate
open RedMagicIce.xcodeproj
```
在 Signing 中选择你自己的 Team,把 `PRODUCT_BUNDLE_IDENTIFIER` 改成唯一值,真机运行(模拟器无蓝牙)。

> ⚠️ 本仓库代码在 Linux 环境编写,**尚未编译/真机测试**;协议来自静态分析,首次连接请从日志面板观察 TX/回包是否符合预期。
