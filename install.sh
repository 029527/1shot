#!/usr/bin/env bash
# 1shot 安装 / 更新 / 卸载
#
#   安装或更新到最新版：
#     curl -fsSL https://raw.githubusercontent.com/029527/1shot/main/install.sh | bash
#   安装指定版本：
#     curl -fsSL https://raw.githubusercontent.com/029527/1shot/main/install.sh | bash -s -- --version 0.2.0
#   完整卸载（App + 设置 + 截图历史 + 缓存）：
#     curl -fsSL https://raw.githubusercontent.com/029527/1shot/main/install.sh | bash -s -- --uninstall
set -euo pipefail

REPO="029527/1shot"
APP_NAME="1shot.app"
BUNDLE_ID="com.1shot.app"
VERSION=""
ACTION="install"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) VERSION="${2#v}"; shift 2 ;;
        --uninstall) ACTION="uninstall"; shift ;;
        -h|--help) sed -n '2,10p' "$0" 2>/dev/null || true; exit 0 ;;
        *) echo "未知参数：$1" >&2; exit 1 ;;
    esac
done

say() { printf '\033[1m==>\033[0m %s\n' "$*"; }
fail() { printf '\033[31m错误：\033[0m%s\n' "$*" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || fail "1shot 只支持 macOS。"
major="$(sw_vers -productVersion | cut -d. -f1)"
[[ "$major" -ge 14 ]] || fail "1shot 需要 macOS 14 或更新版本。"

quit_running() {
    if pgrep -xq 1shot; then
        say "退出正在运行的 1shot"
        osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
        for _ in $(seq 1 20); do pgrep -xq 1shot || return 0; sleep 0.25; done
        pkill -x 1shot || true
    fi
}

installed_app() {
    for dir in /Applications "$HOME/Applications"; do
        [[ -d "$dir/$APP_NAME" ]] && { echo "$dir/$APP_NAME"; return; }
    done
}

if [[ "$ACTION" == "uninstall" ]]; then
    quit_running
    app="$(installed_app || true)"
    [[ -n "$app" ]] && { say "删除 $app"; rm -rf "$app"; }
    say "删除设置、截图历史和缓存"
    defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
    rm -rf "$HOME/Library/Application Support/1shot" "$HOME/Library/Caches/$BUNDLE_ID" \
           "$HOME/Library/Preferences/$BUNDLE_ID.plist"
    say "已卸载。屏幕录制授权请在「系统设置 › 隐私与安全性 › 屏幕录制」里手动移除。"
    exit 0
fi

if [[ -z "$VERSION" ]]; then
    say "查询最新版本"
    tag="$(curl -fsSL -H 'Accept: application/vnd.github+json' "https://api.github.com/repos/$REPO/releases/latest" \
        | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')"
    [[ -n "$tag" ]] || fail "没有找到已发布的版本。"
    VERSION="${tag#v}"
fi

ZIP="1shot-$VERSION.zip"
BASE="https://github.com/$REPO/releases/download/v$VERSION"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

say "下载 1shot $VERSION"
curl -fL --progress-bar -o "$TMP/$ZIP" "$BASE/$ZIP" || fail "下载失败：$BASE/$ZIP"
curl -fsSL -o "$TMP/$ZIP.sha256" "$BASE/$ZIP.sha256" || fail "下载校验文件失败。"
(cd "$TMP" && shasum -a 256 -c "$ZIP.sha256" >/dev/null) || fail "SHA-256 校验失败，已停止安装。"

ditto -x -k "$TMP/$ZIP" "$TMP/unpacked"
[[ -d "$TMP/unpacked/$APP_NAME" ]] || fail "安装包里没有 ${APP_NAME}。"
codesign --verify --deep --strict "$TMP/unpacked/$APP_NAME" || fail "代码签名校验失败。"

DEST="/Applications"
[[ -w "$DEST" ]] || { DEST="$HOME/Applications"; mkdir -p "$DEST"; }

quit_running
say "安装到 $DEST/$APP_NAME"
rm -rf "$DEST/$APP_NAME"
mv "$TMP/unpacked/$APP_NAME" "$DEST/$APP_NAME"
xattr -dr com.apple.quarantine "$DEST/$APP_NAME" 2>/dev/null || true

open "$DEST/$APP_NAME"
say "1shot $VERSION 已安装并启动。首次截图时按提示授权「屏幕录制」。"
