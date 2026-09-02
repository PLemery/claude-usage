#!/usr/bin/env bash
set -euo pipefail

# Default = fast local dev build: ad-hoc signed, never touches Apple, never
# distributable. Pass --release to produce a Developer-ID-signed, hardened
# runtime build ready for ./scripts/notarize.sh and an actual GitHub Release.
#
#   ./scripts/make-app.sh              # local iteration
#   ./scripts/make-app.sh --release    # release candidate
#   ./scripts/make-app.sh --install    # either of the above, then copy to /Applications

RELEASE=false
INSTALL=false
for arg in "$@"; do
  case "$arg" in
    --release) RELEASE=true ;;
    --install) INSTALL=true ;;
  esac
done

swift build -c release
APP="ClaudeUsage.app"
SPARKLE_FRAMEWORK=".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp ".build/release/ClaudeUsageApp" "$APP/Contents/MacOS/ClaudeUsage"
cp "Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp -R "$SPARKLE_FRAMEWORK" "$APP/Contents/Frameworks/Sparkle.framework"

VERSION_SUFFIX=""
if [ "$RELEASE" = false ]; then
  VERSION_SUFFIX="-dev"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>ClaudeUsage</string>
  <key>CFBundleIdentifier</key><string>com.parkerlemery.claudeusage</string>
  <key>CFBundleExecutable</key><string>ClaudeUsage</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.2${VERSION_SUFFIX}</string>
  <key>CFBundleVersion</key><string>3</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>SUFeedURL</key><string>https://raw.githubusercontent.com/PLemery/claude-usage/main/appcast.xml</string>
  <key>SUPublicEDKey</key><string>0VwnlAzTvwyc+TDbjl+Z4bhVAQV29uPNmgaaM29z11s=</string>
  <key>SUEnableAutomaticChecks</key><true/>
  <key>SUScheduledCheckInterval</key><integer>86400</integer>
</dict></plist>
PLIST

SIGN_ID="Developer ID Application: Parker Lemery (XS6TJFT3AH)"
HAVE_DEV_ID=false
security find-identity -v -p codesigning | grep -q "$SIGN_ID" && HAVE_DEV_ID=true

if [ "$RELEASE" = true ] && [ "$HAVE_DEV_ID" = true ]; then
  # Sparkle ships nested XPC services and helper apps. Notarization requires
  # every executable in the bundle to carry OUR signature + hardened runtime,
  # so sign inside-out rather than relying on `--deep` to get it right.
  # --timestamp round-trips to Apple per call, which is why this path is
  # reserved for --release rather than every local rebuild.
  FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
  codesign --force --options runtime --timestamp --sign "$SIGN_ID" \
    "$FRAMEWORK/Versions/B/XPCServices/Downloader.xpc"
  codesign --force --options runtime --timestamp --sign "$SIGN_ID" \
    "$FRAMEWORK/Versions/B/XPCServices/Installer.xpc"
  codesign --force --options runtime --timestamp --sign "$SIGN_ID" \
    "$FRAMEWORK/Versions/B/Autoupdate"
  codesign --force --options runtime --timestamp --sign "$SIGN_ID" \
    "$FRAMEWORK/Versions/B/Updater.app"
  codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$FRAMEWORK"
  codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$APP"
  echo "RELEASE build — signed with $SIGN_ID (hardened runtime, ready for ./scripts/notarize.sh)"
elif [ "$RELEASE" = true ]; then
  echo "error: --release requested but Developer ID cert not found" >&2
  exit 1
else
  # Dev build: ad-hoc signature, no network calls. Fine for local runs —
  # Gatekeeper only checks files quarantined from a download, and this
  # build is never uploaded anywhere.
  codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || echo "warning: codesign skipped"
  echo "DEV build (ad-hoc signed, local only) — pass --release to build a distributable version"
fi
echo "Built $APP"

if [ "$INSTALL" = true ]; then
  DEST="/Applications/$APP"
  rm -rf "$DEST"
  cp -R "$APP" "$DEST"
  echo "Installed to $DEST"
fi
