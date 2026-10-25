# 清晰屏 ClearDisplay

macOS 外接显示器的 **HiDPI 分辨率工具**。给显示器加上系统没给的清晰档位（如 1280×720 / 1440×810 整数倍 HiDPI），让文字和界面更锐利。

> 适用场景：外接 1080p / 2K / 4K 显示器，macOS 默认只给「放大模糊」或「太小」两档，本工具帮你写入真正的 HiDPI 覆盖配置。

---

## 功能

- 列出当前显示器支持的逻辑分辨率，并标注是否为 HiDPI（如 `1280×720（2× HiDPI）`）
- 一键生成覆盖配置：普通档位 + HiDPI 档位，写入系统显示覆盖目录
- 自动识别常见显示器厂商（HKC / DELL / LG / AOC / Samsung / Apple / 虚拟显示器）
- 写入前自动备份到 `~/Documents/display-backup/overrides`，可一键还原或彻底删除恢复系统默认
- 状态实时反馈，操作透明

## 系统要求

- **macOS 14.0 或更新**
- **Apple Silicon（M 系列）**，单架构
- 需要一次**管理员密码**（工具要写 `/Library/Displays/...` 覆盖文件，走系统「批准后以管理员身份运行」）

## 下载与安装

到 **[Releases](https://github.com/zry118/ClearDisplay/releases)** 下载 `ClearDisplay-1.0.zip`，解压后把 `ClearDisplay.app` 拖进「应用程序」。

首次打开 macOS 会拦截（本软件未做 Apple 公证，见下文「关于签名」），二选一即可：

- 右键 `ClearDisplay.app` → 「打开」
- 或终端执行：`xattr -cr /Applications/ClearDisplay.app`

## 使用

1. 打开后选择目标显示器与想要的分辨率档位
2. 点「生成配置」——此时会弹管理员密码框，输入后写入覆盖文件
3. **拔插一下显示器数据线，或重启**，新档位即生效
4. 不满意可「还原备份」或「删除覆盖文件」恢复系统默认

## 关于授权

本软件为**授权制**（带试用）：

- 未授权时为**试用**，有天数限制
- 激活：菜单「输入授权码」粘贴购买后拿到的授权码即可，**离线校验、不需要联网**
- 授权码 = 离线 Ed25519 签名，改动即失效，无法伪造

获取授权码：本软件为付费授权，购买 / 获取方式请见仓库置顶说明或[在此填写你的购买链接 / 联系方式]。

> 你是开发者想自己签发授权码：仓库内 `licensing/licensetool.swift` 提供 `keygen` / `issue` / `verify` 命令，私钥请自己保管（建议 `~/.cleardisplay-key`，权限 600），**不要**放进应用或仓库。

## 关于签名（重要）

本软件目前是 **adhoc 自签名**（开发证书），**没有做 Apple 公证**。原因：公证需要「Developer ID Application」证书 + 付费开发者账号，本仓库发布时未配置。因此：

- 下载后需按上文「右键打开」或 `xattr -cr` 绕过 Gatekeeper
- 若要分发「双击即开」的版本，请用仓库内 `release.sh` 走正式 Developer ID 签名 + 公证流程（需自备证书与 `APPLE_ID` / `TEAM_ID` / `APP_PASSWORD`）

## 为何不走 Mac App Store

工具要向 `/Library/Displays/Contents/Resources/Overrides` 写文件（root 目录），沙盒应用做不到，App Store 版本不可能实现核心功能。只能站点分发 + 公证。

## 源码结构

```
main.swift              主程序（SwiftUI，单文件）
makeicon.swift          程序化生成应用图标（CoreGraphics 画 1024 → iconutil）
licensing/
  licensetool.swift     授权签发 / 校验工具（私钥不入库）
release.sh              正式签名 + 公证 + 装订流程（需 Developer ID 证书）
Info.plist              App 清单（版本号在此）
```

编译（需 Command Line Tools，无需 Xcode）：

```bash
swiftc -sdk $(xcrun --show-sdk-path) -target arm64-apple-macos14.0 -parse-as-library -O main.swift -o ClearDisplay
```

## 版本记录

- **1.0（build 3，2026-10-24）** 初始发布：分辨率列表、HiDPI 覆盖生成、备份/还原、厂商识别、试用 + 离线授权码

## 免责声明

修改系统显示覆盖文件有风险，工具已做备份与还原。使用前建议确认显示器与线材支持目标档位。本软件按「现状」提供，作者不对由此造成的显示异常负责。
