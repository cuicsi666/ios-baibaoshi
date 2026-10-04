# 🧰 百宝箱 Baibaoshi

老板的 iPhone 全能工具台——自研应用融合一体的模块化工具箱。基于 OpenMinis 基座二次开发，SwiftUI 构建，全部按老板需求定制。

## ✨ 模块清单（V8.7）

首页卡片平铺展示，共 7 个模块：

| 模块 | 功能 |
|------|------|
| ⚡️ 电管家 | 充电监控：每 +5% 播报电量和充满预估、三源混合预估引擎（实时速率×历史×参考曲线）、充满提醒、**白班/夜班通知时段**、历史学习、80/90/100 目标电量 |
| ▶️ XVP 播放器 | 内置前端 + **Face ID 解锁**、15 分钟无操作锁定、后台回主页、快照遮罩防偷看 |
| 🖥️ V监控 | ESXi + OpenWrt 直连监控（libssh2 SSH 栈）：温度/CPU/内存/存储、VM 开关、工具箱 |
| 📖 励志成语 | 随机励志成语卡片 |
| 📶 路由器监控 | OpenWrt sysmon 接口实时监控：CPU 曲线、温度、内存、负载、在线设备 |
| 🧠 AI 用量 | ipix 网关每日花销：今日花销 + 电耗 + 请求/Token + **本地历史花销记录**（每日自动累积） |
| ⚙️ 设置 | 白/黑双主题、后台保活（定位+音频双保险）、**检查更新（OTA 一键升级）**、诊断日志上传 |

## 🚀 安装 / 更新

### OTA 一键安装（推荐，秒装）
所有版本采用 **Ad-Hoc 签名**（Apple 证书，设备 UDID 已注册），可通过 iOS 原生 OTA 直接安装。

1. Safari 打开内网分发点：`https://6.6.6.130:8443/baibaoshi/install.html`
2. （首次）安装并信任根证书 `CuicsiCA`：设置 → 通用 → 证书信任设置 → 开启完全信任
3. 复制内网 OTA 链接粘贴到 Safari 地址栏安装：
   ```
   itms-services://?action=download-manifest&url=https://6.6.6.130:8443/baibaoshi/manifest.plist
   ```

### 应用内升级（V8.1+）
百宝箱 → 设置 → 软件更新 → 检查更新 → 立即安装 → 自动打开内网安装页 → 秒装。
（iOS 系统限制：itms-services 仅 Safari 能唤起，故自动跳转 Safari 粘贴链接。）

### 全能签
也可用签名版 IPA 通过全能签/AltStore 安装（全能签证书过期前需重新导出）。

## 🔐 证书说明

- **Apple Ad-Hoc 签名证书**：有效期 **2026-12-04**（约 80 天），到期前需从全能签重新导出 p12 + 描述文件续签（找小龙虾换）
- **自签 CA 证书**：10 年有效，仅用于内网 HTTPS 加密传输，不影响功能

## 📦 分发链路

| 渠道 | 地址 | 说明 |
|------|------|------|
| 源码仓库 | Gitea `cuicsi/ios-baibaoshi`（私有） | 最新代码 + tag V1..V8.7 |
| 构建 | GitHub Actions `cuicsi666/ios-baibaoshi` | push main 自动出 IPA |
| 签名 | zsign（ubuntu）用老板 Ad-Hoc 证书预签 | 出签名版 IPA |
| 内网 OTA | 飞牛 nginx HTTPS `:8443` | 秒下秒装，含 manifest + install.html |
| 更新清单 | 飞牛 `update.json` | App 内检查更新读取 |
| IPA 存档 | 本地下载文件夹 + attachments + 飞牛 `updates/baibaoshi_https/` | 每版留档 |

## 🛠 技术栈

- SwiftUI + Swift Charts（iOS 16+）
- ObjC 混编（V监控 libssh2 SSH 栈）+ C++（InfoNES 游戏内核）+ C（libssh2/mbedtls）
- zsign 服务端预签名 + iOS OTA（itms-services）
- 后台保活：CoreLocation 低功耗定位 + 不可闻音频音轨
- 日志系统：NSSetUncaughtExceptionHandler + signal 崩溃捕获，自动上报飞牛

## 📂 目录结构

```
Baibaoshi/
├── BaibaoshiApp.swift      # 入口 + 全局服务
├── RootView.swift          # 首页卡片网格
├── Theme.swift             # 主题系统（白/黑 + 模块渐变色）
├── SettingsView.swift      # 设置（主题/保活/更新/日志）
├── KeepAliveService.swift  # 后台保活
├── AppLog.swift            # 诊断日志 + 自动上报
├── UpdateService.swift     # OTA 检查/安装
├── ChargeButler/           # 电管家模块
├── Tools/                  # 工具模块（成语/路由监控/AI用量等）
├── VApp/                   # V监控（ObjC + libssh2）
└── Support/                # entitlements + 桥接头
```

## 📌 版本记录

| 版本 | 内容 |
|------|------|
| V1 | 电管家首发：+5% 播报、三源预估、充满提醒、历史学习 |
| V2 | 全应用融合：+XUI遥控、超级按键、流文、龙虾帮、白黑主题、定位保活 |
| V3 | 精简重构：去 XUI/超级按键/龙虾帮，修复启动闪退（单 App Group） |
| V4 | XVP Face ID 解锁、检查更新、卡片缩小、bento 图标 |
| V5 | V监控融合（ObjC + libssh2 + mbedtls 交叉编译） |
| V6 | 游戏机融合（InfoNES 内核 + 71 经典游戏 + 声音 + 8向摇杆） |
| V7 | 游戏机稳定性修复、App 日志系统、电管家详情页通知控制（白班/夜班） |
| V7.1~7.3 | 游戏机按键/声音/画面修复、正版调色板 |
| V8.0~8.2 | V监控背景/应用内 OTA 一键升级、内网秒装分发 |
| V8.3 | AI 用量模块 |
| V8.4 | 去掉分类平铺所有应用、移除流文/游戏机 |
| V8.7 | 移除视频空降模块（当前版） |