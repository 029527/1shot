# 1shot

macOS 菜单栏截图工具（Swift + AppKit，macOS 14+）。

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

签名使用固定的 Apple Development 证书（Team `FYP4TDQ4MV`），重新编译后无需重新授权屏幕录制。
