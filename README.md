# 1shot

macOS 菜单栏截图工具（Swift + AppKit，macOS 14+）：截图、标注、贴图，自动复制和保存。

## 安装

**Homebrew**

```bash
brew tap 029527/1shot https://github.com/029527/1shot
brew install --cask 1shot
```

卸载：`brew uninstall --cask 1shot`；连同设置、截图历史、缓存一起删除：`brew uninstall --zap --cask 1shot`。

**一行命令**

```bash
curl -fsSL https://raw.githubusercontent.com/029527/1shot/main/install.sh | bash
```

- 指定版本：`… | bash -s -- --version 0.2.0`
- 完整卸载：`… | bash -s -- --uninstall`

也可以在 [Releases](https://github.com/029527/1shot/releases) 下载 zip，解压后拖进「应用程序」。

首次截图时按提示在「系统设置 › 隐私与安全性 › 屏幕录制」里允许 1shot，然后重新打开它。

## 更新

1shot 每天自动检查一次 [GitHub Releases](https://github.com/029527/1shot/releases)：

- 默认自动下载新版本，校验 SHA-256 与代码签名后，在 1shot 空闲（没在截图、没有贴图和窗口）或退出时替换并重启；
- 关掉「自动下载并安装」时弹窗询问：立即更新 / 稍后 / 跳过此版本；
- 菜单栏「检查更新…」或设置 › 关于里可以手动检查；
- 只有装在「应用程序」文件夹里的 1shot 会自动替换，开发构建只提示去下载。

## 功能

- 菜单栏常驻，全局快捷键（默认 ⌃⇧A）呼出，多屏定格遮罩
- 窗口识别、框选、控制点调整、方向键微调、放大镜取色（C 复制颜色，⇧ 切换 HEX / RGB）
- 标注：矩形 R、椭圆 O、箭头 A、画笔 P、荧光笔 H、文字 T、序号 N；
  马赛克 M（像素化 / 模糊，画笔涂抹 / 框选区域，可调强度）、高亮 S（矩形 / 椭圆 / 圆角矩形，框外变暗，可调不透明度）、
  水印 W（最多 16 个字，斜向平铺，可调不透明度和颜色）；
  ⌘Z / ⇧⌘Z 撤销重做；不选工具时可选中已有图形移动、改大小、改样式、删除，双击文字重新编辑
- 完成（Enter / 双击 / ✓ / ⌘C）：自动复制（PNG + TIFF）并保存到 `~/Pictures/截图`
- 另存为 ⌘S、贴图到桌面 ⌘T、识别文字 ⌘R、长截图 ⌘L
- 截图历史（菜单栏「截图历史…」，最近 50 条）
- 自定义快捷键（设置 › 快捷键）：
  - 截图：选区后显示工具栏（默认 ⌃⇧A）
  - 截图并复制：选完区域立即复制，不显示工具栏（默认未设置）
  - 贴图：贴剪贴板里的图片 / 文字 / 链接，刚截的图贴回原位置；剪贴板没有可贴内容时贴最近一次截图（默认未设置）
- 圆角与阴影（设置 › 圆角与阴影）：复制和保存时输出四周透明的 PNG；贴图与历史保留原图
- 贴图：滚轮 / 触控板上下滑动或捏合缩放（以光标为中心，往上放大），拖动移动，双击关闭，右键菜单
- 贴图编辑：选中贴图按空格显示 / 隐藏截图工具栏，可在贴图上继续标注、复制、另存、识别文字
- 完成提示：「已复制并保存」等提示上可以点「不再显示」，之后在设置 › 通用里重新打开
- 界面语言：简体中文 / English（设置 › 通用 › 语言，默认跟随系统；文案在 `1shot/Localizable.xcstrings`）
- 不需要「辅助功能」权限，只需要「屏幕录制」权限

## 开发

```bash
xcodegen generate                      # 由 project.yml 生成 1shot.xcodeproj（不进 git）
xcodebuild -project 1shot.xcodeproj -scheme 1shot -derivedDataPath build build
xcodebuild -project 1shot.xcodeproj -scheme 1shot -derivedDataPath build test
open build/Build/Products/Debug/1shot.app
```

查看日志（含「快捷键 → 遮罩可见」耗时）：

```bash
/usr/bin/log stream --predicate 'subsystem == "com.1shot.app"'
```

本地签名使用固定的 Apple Development 证书（Team `FYP4TDQ4MV`），重新编译后无需重新授权屏幕录制。

## 发版

推送 `v*` 标签即可，GitHub Actions（`.github/workflows/release.yml`）会：

1. 用 `scripts/build-release.sh` 构建通用版（arm64 + x86_64），版本号取自标签；
2. 打包 `1shot-<版本>.zip` 与 `.sha256`，创建 Release（自动生成更新说明）；
3. 更新 `Casks/1shot.rb` 的版本号与 SHA-256 并提交到 main。

```bash
git tag v0.2.0
git push origin v0.2.0
```

本地预演：`scripts/build-release.sh 0.2.0`（输出在 `dist/`）。推送到 main 和 PR 会跑 `ci.yml`（构建 + 测试）。

### 签名（可选）

默认使用 ad-hoc 签名：不需要证书，但未经公证，而且每次更新后需要重新授权屏幕录制（系统按签名识别 App）。
在仓库 Settings › Secrets and variables › Actions 里配置以下 Secrets 后，发版会改用证书签名：

| Secret | 内容 |
|---|---|
| `MACOS_CERTIFICATE` | 证书和私钥导出的 .p12，base64 编码（`base64 -i cert.p12 \| pbcopy`） |
| `MACOS_CERTIFICATE_PASSWORD` | .p12 的密码 |
| `MACOS_SIGNING_IDENTITY` | 证书名称，例如 `Developer ID Application: 名字 (TEAMID)` |
| `MACOS_DEVELOPMENT_TEAM` | Team ID |
| `NOTARY_APPLE_ID` / `NOTARY_PASSWORD` | 可选：Apple ID 与 App 专用密码，配合 Developer ID 证书自动公证 |

使用固定证书签名后，更新不再需要重新授权屏幕录制；使用 Developer ID 并公证后，`Casks/1shot.rb` 里去掉隔离属性的 `postflight` 可以删除。
