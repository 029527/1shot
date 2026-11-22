cask "1shot" do
  version "0.1.1"
  sha256 "0b5a72d3f11ee6f688503ac77a0a3cca6d1de7732952e18fde269ac846571fd2"

  url "https://github.com/029527/1shot/releases/download/v#{version}/1shot-#{version}.zip"
  name "1shot"
  desc "Menu bar screenshot tool: capture, annotate, pin"
  homepage "https://github.com/029527/1shot"

  # App 自带检查更新（GitHub Releases），brew upgrade 不会和它冲突。
  auto_updates true
  depends_on macos: :sonoma

  app "1shot.app"

  # 发版构建默认是 ad-hoc 签名、未经公证：去掉下载带来的隔离属性，否则 Gatekeeper 会拦截打开。
  # 配置了 Developer ID 证书并公证后可以删掉这一段。
  postflight_steps do
    run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{appdir}}/1shot.app"], must_succeed: false
  end

  uninstall quit: "com.1shot.app"

  # brew uninstall --zap 1shot：连同设置、截图历史、缓存一起删除。
  zap trash: [
    "~/Library/Application Support/1shot",
    "~/Library/Caches/com.1shot.app",
    "~/Library/Preferences/com.1shot.app.plist",
  ]
end
