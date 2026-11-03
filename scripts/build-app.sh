#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
if [[ "${IPHONIFY_RELEASE_BUILD:-0}" = 1 ]]; then
 [[ "${SIGN_IDENTITY:-}" = 'Developer ID Application:'* ]] || { print -u2 'Release builds require a Developer ID Application identity'; exit 1; }
 [[ -s config/sparkle-public-key.txt ]] || { print -u2 'Configure the iPhonify update public key before a release build'; exit 1; }
fi
# Keep a developer's local TCC identity stable without committing it to the repo.
if [[ "${IPHONIFY_RELEASE_BUILD:-0}" != 1 && -z "${SIGN_IDENTITY:-}" && -s .local/signing-identity.txt ]]; then
 SIGN_IDENTITY="$(cat .local/signing-identity.txt)"
fi
./scripts/fetch-sparkle.sh
FRAMEWORKS="$PWD/build/sparkle/Sparkle.xcframework/macos-arm64_x86_64"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
# SwiftBuild currently stamps the deployment target as LC_BUILD_VERSION.sdk.
# The native SwiftPM backend links against the selected SDK, matching MagDot.
BUILD_ARGS=(-c release --build-system native --sdk "$SDK_PATH" --scratch-path "$PWD/.build/native")
swift build "${BUILD_ARGS[@]}" -Xswiftc -F -Xswiftc "$FRAMEWORKS" -Xlinker -F -Xlinker "$FRAMEWORKS" -Xlinker -rpath -Xlinker @executable_path/../Frameworks
APP="${IPHONIFY_APP_PATH:-$PWD/build/iPhonify.app}"
BUNDLE_ID="${IPHONIFY_BUNDLE_IDENTIFIER:-com.maximkich.iphonify}"
# Disposable development bundles must not compete with the real app in
# LaunchServices or cause System Settings to relaunch a different binary.
if [[ "${IPHONIFY_RELEASE_BUILD:-0}" != 1 && -z "${IPHONIFY_BUNDLE_IDENTIFIER:-}" && "${APP:A}" != "$PWD/build/iPhonify.app" ]]; then
 BUNDLE_ID="com.maximkich.iphonify.validation"
fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Legal"
BIN_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
cp "$BIN_DIR/iPhonify" "$APP/Contents/MacOS/iPhonify"
python3 scripts/check-linked-sdk.py "$APP/Contents/MacOS/iPhonify"
ICONSET="$PWD/build/AppIcon.iconset"
mkdir -p "$ICONSET"
swift scripts/make-app-icon.swift assets/AppIconArtwork.png build/AppIcon.png
for SIZE in 16 32 128 256 512; do
 sips -z "$SIZE" "$SIZE" build/AppIcon.png --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
 DOUBLE=$((SIZE * 2))
 sips -z "$DOUBLE" "$DOUBLE" build/AppIcon.png --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
python3 - "$APP/Contents/Info.plist" "$BUNDLE_ID" <<'PY'
import plistlib
from pathlib import Path
info=dict(CFBundleExecutable='iPhonify',CFBundlePackageType='APPL',CFBundleIdentifier=__import__('sys').argv[2],CFBundleName='iPhonify',CFBundleDisplayName='iPhonify',CFBundleIconFile='AppIcon',CFBundleVersion=Path('BUILD_NUMBER').read_text().strip(),CFBundleShortVersionString=Path('VERSION').read_text().strip(),LSMinimumSystemVersion='14.0',LSUIElement=True,NSHighResolutionCapable=True,NSScreenCaptureUsageDescription='Create a temporary app snapshot for the swipe-home animation. Screen images stay in memory.')
with open(__import__('sys').argv[1], 'wb') as f: plistlib.dump(info,f)
PY
cp LICENSE ACKNOWLEDGEMENTS.md docs/licenses/InstantSpaceSwitcher-MIT.txt "$APP/Contents/Resources/Legal/"
mkdir -p "$APP/Contents/Frameworks"
ditto "$FRAMEWORKS/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
python3 scripts/thin-sparkle.py "$APP"
cp docs/licenses/Sparkle-LICENSE.txt "$APP/Contents/Resources/Legal/"
python3 scripts/configure-updater.py "$APP/Contents/Info.plist" config/sparkle-public-key.txt
IDENTITY="${SIGN_IDENTITY:--}"
MODE=development
if [[ "${IPHONIFY_RELEASE_BUILD:-0}" = 1 ]]; then
 [[ "$IDENTITY" != - ]] || { print -u2 'Release builds require SIGN_IDENTITY'; exit 1; }
 MODE=release
fi
scripts/sign-sparkle.sh "$APP" "$IDENTITY" "$MODE"
SIGN_OPTIONS=(--timestamp=none)
if [[ "$MODE" = release ]]; then SIGN_OPTIONS=(--options runtime --timestamp); fi
codesign --force --sign "$IDENTITY" "${SIGN_OPTIONS[@]}" "$APP"
codesign --verify --deep --strict "$APP"
"$APP/Contents/MacOS/iPhonify" --self-test
print "$APP"
