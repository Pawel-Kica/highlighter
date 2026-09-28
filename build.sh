#!/bin/sh
# Builds and installs /Applications/Highlighter.app (Spotlight and Raycast find it there).
# A running copy keeps the old build until relaunched: pkill -x Highlighter; open /Applications/Highlighter.app
set -e
cd "$(dirname "$0")"
APP=/Applications/Highlighter.app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp AppIcon.icns "$APP/Contents/Resources/" # from make-icon.swift
swiftc -O main.swift -o /tmp/Highlighter.new
mv /tmp/Highlighter.new "$APP/Contents/MacOS/Highlighter" # rename, so a running copy doesn't crash
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Highlighter</string>
  <key>CFBundleIdentifier</key><string>com.pawelkica.highlighter</string>
  <key>CFBundleExecutable</key><string>Highlighter</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSUIElement</key><true/>
  <key>CFBundleIconFile</key><string>AppIcon</string>
</dict>
</plist>
EOF
xattr -cr "$APP" # Finder attributes make codesign fail
codesign --force -s - "$APP"
