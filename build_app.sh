#!/bin/bash
# RTX ConfigMaker を .app バンドルとしてビルドし、ダブルクリックで起動できるようにする
set -e
cd "$(dirname "$0")"

APP="RTX ConfigMaker.app"
BIN="RTXConfigMaker"

echo "▶ リリースビルド中..."
swift build -c release

echo "▶ .app バンドルを作成中..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp ".build/release/$BIN" "$APP/Contents/MacOS/$BIN"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>RTX ConfigMaker</string>
    <key>CFBundleDisplayName</key><string>RTX ConfigMaker</string>
    <key>CFBundleIdentifier</key><string>io.github.okamurax.rtxconfigmaker</string>
    <key>CFBundleVersion</key><string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleExecutable</key><string>$BIN</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
EOF

# ローカル実行用のアドホック署名
codesign --force --deep --sign - "$APP" 2>/dev/null || true

echo "✅ 完成: $APP"
echo "   → ダブルクリック、または  open \"$APP\"  で起動できます"
