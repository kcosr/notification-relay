#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
bin_dir="$(swift build -c release --show-bin-path)"
app_path="$PWD/dist/Notification Relay.app"
mkdir -p "$app_path/Contents/MacOS"
cp "$bin_dir/notification-relay" "$app_path/Contents/MacOS/notification-relay"
cat > "$app_path/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>local.notification-relay.app</string>
  <key>CFBundleName</key><string>Notification Relay</string>
  <key>CFBundleDisplayName</key><string>Notification Relay</string>
  <key>CFBundleExecutable</key><string>notification-relay</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$app_path"
codesign --verify --strict "$app_path"
printf 'Built %s\n' "$app_path"
