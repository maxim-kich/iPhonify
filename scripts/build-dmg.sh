#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
export IPHONIFY_DMG_APP="$1"
output="$2"
test ! -e "$output"
staging=$(mktemp -d "${TMPDIR:-/tmp}/iphonify-dmg.XXXXXX")
trap 'rm -rf "$staging"' EXIT
swift scripts/render-dmg-background.swift "$staging/installer.tiff"
export IPHONIFY_DMG_BACKGROUND="$staging/installer.tiff"
uvx --from dmgbuild==1.6.7 dmgbuild -s scripts/dmg-settings.py iPhonify "$output"
hdiutil verify "$output"
