# SnapMark

macOS 菜单栏截图工具（Swift + AppKit，macOS 14+）。

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
