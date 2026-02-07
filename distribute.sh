#!/bin/bash
set -euo pipefail

# ============================================================
# DualCast Distribution Script
# Builds, signs, notarizes, and creates a DMG for distribution
# ============================================================
#
# Prerequisites:
#   1. Apple Developer Program membership ($99/year)
#   2. "Developer ID Application" certificate installed in Keychain
#      - Open Xcode → Settings → Accounts → Manage Certificates → + Developer ID Application
#   3. App-specific password for notarization
#      - Create at https://appleid.apple.com → Sign-In and Security → App-Specific Passwords
#
# Usage:
#   ./distribute.sh --apple-id "you@email.com" --team-id "XXXXXXXXXX" --password "xxxx-xxxx-xxxx-xxxx"
#
# To find your Team ID:
#   Open Keychain Access → search "Developer ID" → look at Organizational Unit
#

APPLE_ID=""
TEAM_ID=""
APP_PASSWORD=""
SCHEME="DualCast"
PROJECT="DualCast.xcodeproj"
BUILD_DIR="build"
APP_NAME="DualCast"
DMG_NAME="DualCast-1.0.0"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --apple-id) APPLE_ID="$2"; shift 2 ;;
        --team-id) TEAM_ID="$2"; shift 2 ;;
        --password) APP_PASSWORD="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

if [[ -z "$APPLE_ID" || -z "$TEAM_ID" || -z "$APP_PASSWORD" ]]; then
    echo "Usage: ./distribute.sh --apple-id EMAIL --team-id TEAMID --password APP_SPECIFIC_PASSWORD"
    exit 1
fi

cd "$(dirname "$0")"

echo "==> Cleaning previous build..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> Building Release archive..."
xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$BUILD_DIR/$APP_NAME.xcarchive" \
    CODE_SIGN_IDENTITY="Developer ID Application" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_STYLE=Manual \
    | tail -5

echo "==> Exporting app from archive..."
cat > "$BUILD_DIR/export.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>${TEAM_ID}</string>
</dict>
</plist>
EOF

xcodebuild -exportArchive \
    -archivePath "$BUILD_DIR/$APP_NAME.xcarchive" \
    -exportPath "$BUILD_DIR/export" \
    -exportOptionsPlist "$BUILD_DIR/export.plist" \
    | tail -5

APP_PATH="$BUILD_DIR/export/$APP_NAME.app"

echo "==> Verifying code signature..."
codesign --verify --deep --strict "$APP_PATH"
echo "    ✓ Signature valid"

echo "==> Creating DMG..."
DMG_PATH="$BUILD_DIR/$DMG_NAME.dmg"
hdiutil create -volname "$APP_NAME" \
    -srcfolder "$APP_PATH" \
    -ov -format UDZO \
    "$DMG_PATH" \
    | tail -2

echo "==> Submitting for notarization..."
xcrun notarytool submit "$DMG_PATH" \
    --apple-id "$APPLE_ID" \
    --team-id "$TEAM_ID" \
    --password "$APP_PASSWORD" \
    --wait

echo "==> Stapling notarization ticket..."
xcrun stapler staple "$DMG_PATH"

echo ""
echo "============================================"
echo "✓ Done! Distributable DMG is at:"
echo "  $DMG_PATH"
echo ""
echo "Users can download and drag DualCast.app"
echo "to /Applications. macOS will trust it."
echo "============================================"
