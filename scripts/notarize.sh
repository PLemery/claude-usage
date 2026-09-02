#!/usr/bin/env bash
set -euo pipefail

APP="ClaudeUsage.app"
ZIP="ClaudeUsage.zip"
PROFILE="notarytool-profile"

if [ ! -d "$APP" ]; then
  echo "error: $APP not found — run ./scripts/make-app.sh first" >&2
  exit 1
fi

echo "Submitting $APP for notarization..."
SUBMIT_ZIP="ClaudeUsage-submission.zip"
ditto -c -k --keepParent "$APP" "$SUBMIT_ZIP"
xcrun notarytool submit "$SUBMIT_ZIP" --keychain-profile "$PROFILE" --wait
rm -f "$SUBMIT_ZIP"

echo "Stapling notarization ticket..."
xcrun stapler staple "$APP"

echo "Building final distributable zip..."
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo "Done: $ZIP is notarized and ready to distribute."
