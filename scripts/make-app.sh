#!/usr/bin/env bash
set -euo pipefail
swift build -c release
APP="ClaudeUsage.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp ".build/release/ClaudeUsageApp" "$APP/Contents/MacOS/ClaudeUsage"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>ClaudeUsage</string>
  <key>CFBundleIdentifier</key><string>com.parkerlemery.claudeusage</string>
  <key>CFBundleExecutable</key><string>ClaudeUsage</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
</dict></plist>
PLIST

# Ad-hoc code signature → stable identity so macOS doesn't re-prompt for
# Keychain access on every rebuild, and so launch-at-login works.
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || echo "warning: codesign skipped"
echo "Built $APP"

# Optional: ./scripts/make-app.sh --install  → copy into /Applications
if [ "${1:-}" = "--install" ]; then
  DEST="/Applications/$APP"
  rm -rf "$DEST"
  cp -R "$APP" "$DEST"
  echo "Installed to $DEST"
fi
