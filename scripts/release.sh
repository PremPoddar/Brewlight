#!/bin/zsh
# Builds, signs, notarizes and packages a release.
#
# Required environment:
#   DEVELOPER_ID      "Developer ID Application: Your Name (TEAMID)"
#   NOTARY_PROFILE    keychain profile created with `xcrun notarytool store-credentials`
# Optional:
#   SPARKLE_BIN       path to Sparkle's bin/ (for generate_appcast, once Sparkle is integrated)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(awk -F' = ' '/^APP_VERSION/{print $2}' Config/App.xcconfig)
DIST=dist
APP="$DIST/export/Brewlight.app"
DMG="$DIST/Brewlight-$VERSION.dmg"
: "${DEVELOPER_ID:?set DEVELOPER_ID}"
: "${NOTARY_PROFILE:?set NOTARY_PROFILE}"

rm -rf "$DIST" && mkdir -p "$DIST"
xcodegen generate

echo "==> Archiving $VERSION (universal)"
xcodebuild -scheme Brewlight -configuration Release -archivePath "$DIST/Brewlight.xcarchive" \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="$DEVELOPER_ID" CODE_SIGN_STYLE=Manual OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime" \
  archive

mkdir -p "$DIST/export"
cp -R "$DIST/Brewlight.xcarchive/Products/Applications/Brewlight.app" "$APP"
codesign --verify --deep --strict "$APP"

echo "==> Building DMG"
STAGE="$DIST/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Brewlight" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
codesign --sign "$DEVELOPER_ID" --timestamp "$DMG"

echo "==> Notarizing"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"

if [[ -n "${SPARKLE_BIN:-}" ]]; then
  echo "==> Generating appcast"
  "$SPARKLE_BIN/generate_appcast" "$DIST"
fi

SHA=$(shasum -a 256 "$DMG" | awk '{print $1}')
echo
echo "Cask lines for Casks/brewlight.rb:"
echo "  version \"$VERSION\""
echo "  sha256 \"$SHA\""
