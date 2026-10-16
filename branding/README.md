# 極凍 Cryo 品牌素材

圖示由 `logo.svg.js` 產生(冰藍渦旋扇葉 + 中心雪花 + 冰環),修改後重新輸出:

```
cd branding && NODE_PATH=$(npm root -g) node render.js
```

輸出 `AppIcon.png`(1024×1024、不透明,iOS App 圖示)與 `Logo.png`(透明背景,App 內使用),
再複製到 `RedMagicIce/Assets.xcassets` 對應資料夾。AppIcon 必須去掉 alpha 通道。
