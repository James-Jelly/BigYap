#!/bin/bash
# Build the macOS app in Release and package it as a distributable DMG.
#
# Signing: uses Developer ID if a certificate is installed (no Gatekeeper
# warnings for the recipient), otherwise falls back to an ad-hoc signature —
# the app still runs, but the recipient must approve it once in
# System Settings > Privacy & Security.
set -euo pipefail

cd "$(dirname "$0")/.."
BUILD=build/dmg
STAGE="$BUILD/stage"
rm -rf "$BUILD"
mkdir -p "$STAGE"

# Pick the Developer ID Application certificate. Set SIGNING_IDENTITY to a
# SHA-1 hash to force one; otherwise the most recently issued one wins, so a
# reissued certificate (say, after a team rename) is used automatically.
IDENTITY="${SIGNING_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
  IDENTITY=$(security find-identity -v -p codesigning \
    | grep "Developer ID Application" | awk '{print $2}' \
    | while read -r hash; do
        start=$(security find-certificate -a -c "Developer ID Application" -Z -p 2>/dev/null \
          | awk -v h="$hash" 'BEGIN{RS="-----END CERTIFICATE-----"} $0 ~ h {print $0 "-----END CERTIFICATE-----"}' \
          | openssl x509 -noout -startdate 2>/dev/null | cut -d= -f2)
        [ -n "$start" ] || start="Jan 1 00:00:00 1970 GMT"
        echo "$(date -j -f "%b %d %T %Y %Z" "$start" +%s 2>/dev/null || echo 0) $hash"
      done | sort -n | tail -1 | awk '{print $2}' || true)
fi
if [ -n "$IDENTITY" ]; then
  echo "Signing with Developer ID $IDENTITY"
  security find-identity -v -p codesigning | grep "$IDENTITY" | sed 's/^ *[0-9]*) //' 
  SIGN_ARGS=(CODE_SIGN_IDENTITY="$IDENTITY" CODE_SIGN_STYLE=Manual \
             PROVISIONING_PROFILE_SPECIFIER="" \
             CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
             OTHER_CODE_SIGN_FLAGS="--timestamp -o runtime")
else
  echo "No Developer ID certificate found — signing ad-hoc."
  SIGN_ARGS=(CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual PROVISIONING_PROFILE_SPECIFIER="")
fi

xcodebuild -project bigyap.xcodeproj -scheme bigyap -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$BUILD/dd" \
  "${SIGN_ARGS[@]}" build

APP=$(find "$BUILD/dd/Build/Products/Release" -maxdepth 1 -name '*.app' | head -1)
[ -n "$APP" ] || { echo "No .app produced"; exit 1; }
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
  "$STAGE/$(basename "$APP")/Contents/Info.plist")
DMG="build/BigYap-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "BigYap $VERSION" -srcfolder "$STAGE" \
  -ov -format UDZO "$DMG"

if [ -n "$IDENTITY" ]; then
  codesign --sign "$IDENTITY" --timestamp "$DMG"

  # Notarise, if credentials have been stored once with:
  #   xcrun notarytool store-credentials bigyap --apple-id <id> \
  #     --team-id <team-id> --password <app-specific-password>
  if xcrun notarytool history --keychain-profile bigyap >/dev/null 2>&1; then
    echo "Submitting for notarisation..."
    xcrun notarytool submit "$DMG" --keychain-profile bigyap --wait
    xcrun stapler staple "$DMG"
    spctl -a -vvv -t open --context context:primary-signature "$DMG"
  else
    echo "No 'bigyap' notarytool profile — skipping notarisation."
  fi
fi
echo "Created $DMG"
