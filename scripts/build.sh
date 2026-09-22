#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
# 使用命令行工具构建，无需启动 Xcode。
if [[ -z "${DEVELOPER_DIR:-}" && -d /Library/Developer/CommandLineTools ]]; then
  export DEVELOPER_DIR=/Library/Developer/CommandLineTools
fi
BUILD_ARGS=(--build-system native)
if [[ -d /Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk ]]; then
  BUILD_ARGS+=(--sdk /Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk)
fi
swift build "${BUILD_ARGS[@]}" -c release
APP_PATH="$PWD/dist/手势计时器.app"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
BIN_PATH="$(swift build "${BUILD_ARGS[@]}" -c release --show-bin-path)"
cp "$BIN_PATH/TimeSensitive" "$APP_PATH/Contents/MacOS/TimeSensitive"
cat > "$APP_PATH/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>手势计时器</string>
  <key>CFBundleDisplayName</key><string>手势计时器</string>
  <key>CFBundleIdentifier</key><string>dev.local.TimeSensitive</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>CFBundleExecutable</key><string>TimeSensitive</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
swift -sdk "$(xcrun --show-sdk-path)" scripts/icon.swift "$PWD/dist"
iconutil -c icns "$PWD/dist/AppIcon.iconset" -o "$APP_PATH/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$APP_PATH"
print "已构建：$APP_PATH"
