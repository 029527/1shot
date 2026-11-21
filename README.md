# SnapMark

macOS 菜单栏截图工具（Swift + AppKit，macOS 14+）。

## 功能

- 菜单栏常驻，全局快捷键（默认 ⌃⇧A）呼出，多屏定格遮罩
- 窗口识别、框选、控制点调整、方向键微调、放大镜取色（C 复制颜色，⇧ 切换 HEX / RGB）
- 标注：矩形 R、椭圆 O、箭头 A、画笔 P、荧光笔 H、文字 T、序号 N、马赛克 M；
  ⌘Z / ⇧⌘Z 撤销重做；不选工具时可选中已有图形移动、改大小、改样式、删除，双击文字重新编辑
- 完成（Enter / 双击 / ✓ / ⌘C）：自动复制（PNG + TIFF）并保存到 `~/Pictures/截图`
- 另存为 ⌘S、贴图到桌面 ⌘T、识别文字 ⌘R、长截图 ⌘L
- 截图历史（菜单栏「截图历史…」，最近 50 条）
- 不需要「辅助功能」权限，只需要「屏幕录制」权限

## 开发

```bash
xcodegen generate                      # 由 project.yml 生成 SnapMark.xcodeproj（不进 git）
xcodebuild -project SnapMark.xcodeproj -scheme SnapMark -derivedDataPath build build
xcodebuild -project SnapMark.xcodeproj -scheme SnapMark -derivedDataPath build test
open build/Build/Products/Debug/SnapMark.app
```

查看日志（含「快捷键 → 遮罩可见」耗时）：

```bash
/usr/bin/log stream --predicate 'subsystem == "com.snapmark.SnapMark"'
```

签名使用固定的 Apple Development 证书（Team `FYP4TDQ4MV`），重新编译后无需重新授权屏幕录制。
