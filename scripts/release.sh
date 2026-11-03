#!/bin/zsh
# Builds and packages a release as dist/Brewlight.dmg.
#
# Optional environment (both set: signed with Developer ID and notarized; otherwise ad-hoc signed):
#   DEVELOPER_ID      "Developer ID Application: Your Name (TEAMID)"
#   NOTARY_PROFILE    keychain profile created with `xcrun notarytool store-credentials`
#   SPARKLE_BIN       path to Sparkle's bin/ (for generate_appcast, once Sparkle is integrated)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(awk -F' = ' '/^APP_VERSION/{print $2}' Config/App.xcconfig)
DIST=dist
APP="$DIST/export/Brewlight.app"
# A fixed name keeps releases/latest/download/Brewlight.dmg pointing at the newest build.
DMG="$DIST/Brewlight.dmg"
SIGNED=$([[ -n "${DEVELOPER_ID:-}" && -n "${NOTARY_PROFILE:-}" ]] && echo 1 || echo 0)

rm -rf "$DIST" && mkdir -p "$DIST"
xcodegen generate

echo "==> Archiving $VERSION (universal)"
if (( SIGNED )); then
  SIGN_ARGS=(CODE_SIGN_IDENTITY="$DEVELOPER_ID" CODE_SIGN_STYLE=Manual OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime")
else
  echo "    DEVELOPER_ID or NOTARY_PROFILE not set: ad-hoc signing, no notarization"
  SIGN_ARGS=(CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=)
fi
xcodebuild -scheme Brewlight -configuration Release -archivePath "$DIST/Brewlight.xcarchive" \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO "${SIGN_ARGS[@]}" archive

mkdir -p "$DIST/export"
cp -R "$DIST/Brewlight.xcarchive/Products/Applications/Brewlight.app" "$APP"
codesign --verify --deep --strict "$APP"

echo "==> Building DMG"
STAGE="$DIST/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Brewlight" -srcfolder "$STAGE" -ov -format UDZO "$DMG"

if (( SIGNED )); then
  codesign --sign "$DEVELOPER_ID" --timestamp "$DMG"
  echo "==> Notarizing"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
fi

if [[ -n "${SPARKLE_BIN:-}" ]]; then
  echo "==> Generating appcast"
  "$SPARKLE_BIN/generate_appcast" "$DIST"
fi

SHA=$(shasum -a 256 "$DMG" | awk '{print $1}')
echo
echo "Cask lines for Casks/brewlight.rb:"
echo "  version \"$VERSION\""
echo "  sha256 \"$SHA\""
