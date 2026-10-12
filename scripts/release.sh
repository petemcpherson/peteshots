#!/usr/bin/env bash
set -euo pipefail

APP="Peteshots"
VERSION="${1:?usage: release.sh <marketing-version> <build-number>}"
BUILD="${2:?usage: release.sh <marketing-version> <build-number>}"
TEAM="${DEVELOPMENT_TEAM:-A2T9Q78M27}"
PROFILE="${NOTARY_PROFILE:-petekm-notary}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/build"
ARCHIVE="$OUT/$APP.xcarchive"
EXPORT_DIR="$OUT/export"
STAGING="$OUT/dmg"
DMG="$OUT/$APP-$VERSION.dmg"

rm -rf "$OUT"
mkdir -p "$OUT" "$EXPORT_DIR" "$STAGING"

cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>developer-id</string>
    <key>teamID</key><string>$TEAM</string>
    <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
PLIST

echo "==> Archiving $VERSION ($BUILD)"
xcodebuild -project "$ROOT/$APP.xcodeproj" -scheme "$APP" -configuration Release \
    -archivePath "$ARCHIVE" \
    MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" \
    DEVELOPMENT_TEAM="$TEAM" \
    archive

echo "==> Exporting with Developer ID"
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
    -exportOptionsPlist "$OUT/ExportOptions.plist" \
    -exportPath "$EXPORT_DIR"

codesign --verify --deep --strict --verbose=2 "$EXPORT_DIR/$APP.app"
echo "==> Architectures: $(lipo -archs "$EXPORT_DIR/$APP.app/Contents/MacOS/$APP")"

echo "==> Building disk image"
cp -R "$EXPORT_DIR/$APP.app" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "$APP" -srcfolder "$STAGING" -ov -format UDZO "$DMG"

echo "==> Signing disk image"
codesign --force --sign "Developer ID Application: Peter McPherson ($TEAM)" --timestamp "$DMG"

echo "==> Notarizing (this waits for Apple)"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait

echo "==> Stapling"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

echo "==> Done: $DMG"
shasum -a 256 "$DMG"
