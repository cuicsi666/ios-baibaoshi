# 百宝箱 Baibaoshi V2 🧰

老板的 iPhone 全能工具台——全部自研应用融合一体，卡片式模块化仪表盘。

## 模块清单

**应用区**
- ⚡️ **电管家**：充电监控（每 +5% 推送电量+充满预估、三源混合预估引擎、历史学习、充满提醒、80/90/100 目标）
- 🎛️ **XUI 遥控**：XUI 智能桌面伴侣（蓝牙遥控 / 复古手柄 / 蓝牙上网中继）
- 🎙️ **超级按键**：说话 → 飞牛中转 → MiMo 识别 → 小龙虾对话 → 飞书播报
- ✍️ **流文**：板子说话 BLE 逐字流入任意输入框（含自定义键盘扩展，App Group 无缝衔接）
- 🌐 **龙虾帮**：OpenClaw 控制台三端切换 WebView

**工具区**（原百宝匣七件套）
- 震动实验室 / 音量测试 / API 实验室 / 励志成语 / 路由器监控 / 导航站 / AI 音乐

## 核心能力

- **白/黑双主题**：导航栏一键切换，默认浅色，全局自适应
- **后台常驻保活**：低功耗定位（3km 精度，仅保活不采集）+ 充电时不可闻音轨双保险，防 iOS 冻结
- **卡片式 UI**：两列模块卡片 + 分组（应用/工具），问候语头部

## 构建

GitHub Actions（macos-15 + XcodeGen）出未签名 IPA；Gitea Release 归档。

```
xcodegen generate
xcodebuild archive -project Baibaoshi.xcodeproj -scheme Baibaoshi \
  -destination 'generic/platform=iOS' -archivePath build/Bai.xcarchive \
  CODE_SIGNING_ALLOWED=NO
```

## 来源仓库（已归档融合）

ios-cuibox（百宝匣基底）/ ios-chargebutler / ios-feishu-voice（xui-ble-keepalive v4.3）/ ios-superkey / ios-flowtext / ios-longxia-bang
