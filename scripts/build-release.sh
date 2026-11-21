#!/usr/bin/env bash
# 构建发版用的 1shot.app（Apple 芯片 + Intel 通用），打包成 zip 并生成 SHA-256。
#
#   scripts/build-release.sh 0.2.0
#
# 签名：
#   - 设置了 SIGNING_IDENTITY（例如 "Developer ID Application: Name (TEAMID)"）和 DEVELOPMENT_TEAM 时用它签名；
#   - 否则 ad-hoc 签名（不需要证书；用户首次打开、每次更新后需要重新授权屏幕录制）。
# 公证（可选）：同时设置 NOTARY_APPLE_ID、NOTARY_PASSWORD（App 专用密码）、DEVELOPMENT_TEAM 且使用 Developer ID 证书时进行。
# 输出：dist/1shot-<version>.zip 与 dist/1shot-<version>.zip.sha256
set -euo pipefail

VERSION="${1:?用法：scripts/build-release.sh <版本号，例如 0.2.0>}"
VERSION="${VERSION#v}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BUILD_DIR="$ROOT/build/release"
DIST_DIR="$ROOT/dist"
APP="$BUILD_DIR/Build/Products/Release/1shot.app"
ZIP="$DIST_DIR/1shot-$VERSION.zip"

command -v xcodegen >/dev/null || { echo "需要 xcodegen：brew install xcodegen" >&2; exit 1; }
xcodegen generate --quiet

SIGNING=(CODE_SIGN_STYLE=Manual)
if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
    echo "==> 使用证书签名：$SIGNING_IDENTITY"
    SIGNING+=(CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:?需要 DEVELOPMENT_TEAM}"
              "OTHER_CODE_SIGN_FLAGS=--timestamp")
else
    echo "==> 没有配置证书，使用 ad-hoc 签名"
    SIGNING+=(CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=)
fi

rm -rf "$BUILD_DIR" "$DIST_DIR"
mkdir -p "$DIST_DIR"

echo "==> 构建 1shot $VERSION（arm64 + x86_64）"
xcodebuild -project 1shot.xcodeproj -scheme 1shot -configuration Release \
    -derivedDataPath "$BUILD_DIR" -destination 'generic/platform=macOS' \
    ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
    MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$VERSION" \
    "${SIGNING[@]}" \
    build | grep -E "error:|warning: .*1shot/|BUILD" || true
[[ -d "$APP" ]] || { echo "构建失败：找不到 $APP" >&2; exit 1; }

echo "==> 校验签名与版本"
codesign --verify --deep --strict --verbose=1 "$APP"
BUILT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
[[ "$BUILT_VERSION" == "$VERSION" ]] || { echo "版本号不一致：$BUILT_VERSION ≠ $VERSION" >&2; exit 1; }
lipo -archs "$APP/Contents/MacOS/1shot"

if [[ -n "${SIGNING_IDENTITY:-}" && "$SIGNING_IDENTITY" == Developer\ ID* \
      && -n "${NOTARY_APPLE_ID:-}" && -n "${NOTARY_PASSWORD:-}" ]]; then
    echo "==> 公证"
    NOTARIZE_ZIP="$BUILD_DIR/notarize.zip"
    ditto -c -k --keepParent "$APP" "$NOTARIZE_ZIP"
    xcrun notarytool submit "$NOTARIZE_ZIP" --apple-id "$NOTARY_APPLE_ID" --password "$NOTARY_PASSWORD" \
        --team-id "$DEVELOPMENT_TEAM" --wait
    xcrun stapler staple "$APP"
fi

echo "==> 打包"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
(cd "$DIST_DIR" && shasum -a 256 "$(basename "$ZIP")" > "$(basename "$ZIP").sha256")
cat "$ZIP.sha256"
echo "完成：$ZIP"
