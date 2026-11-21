#!/usr/bin/env bash
# 发版后更新 Casks/1shot.rb 的版本号与 SHA-256。
#   scripts/update-cask.sh 0.2.0 <sha256>
set -euo pipefail
VERSION="${1:?版本号}"; VERSION="${VERSION#v}"
SHA="${2:?sha256}"
CASK="$(cd "$(dirname "$0")/.." && pwd)/Casks/1shot.rb"
/usr/bin/sed -i '' -E "s/^  version \".*\"/  version \"$VERSION\"/; s/^  sha256 .*/  sha256 \"$SHA\"/" "$CASK"
grep -E '^  (version|sha256) ' "$CASK"
