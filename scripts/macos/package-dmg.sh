#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$ROOT/scripts/macos/env.sh"

VERSION="${VERSION:-$(awk -F"'" '/version:/ { print $2; exit }' "$ROOT/meson.build")}"
ARCH="${ARCH:-$(uname -m)}"
APP_DIR="${APP_DIR:-$ROOT/dist/macos/Parla.app}"
DMG_DIR="${DMG_DIR:-$ROOT/dist/macos}"
DMG="$DMG_DIR/Parla-$VERSION-$ARCH.dmg"
APP_BASENAME="$(basename "$APP_DIR")"

make -C "$ROOT" all BUILD_DIR="${BUILD_DIR:-$ROOT/builddir}" BUILDTYPE="${BUILDTYPE:-release}"
APP_DIR="$APP_DIR" VERSION="$VERSION" "$ROOT/scripts/macos/bundle.sh" >/dev/null

mkdir -p "$DMG_DIR"
rm -f "$DMG"

staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
cp -R "$APP_DIR" "$staging/"

if command -v create-dmg >/dev/null 2>&1; then
    create-dmg \
        --volname "Parla" \
        --window-pos 200 120 \
        --window-size 600 400 \
        --icon-size 100 \
        --icon "$APP_BASENAME" 150 185 \
        --app-drop-link 450 185 \
        --no-internet-enable \
        "$DMG" \
        "$staging"
else
    ln -s /Applications "$staging/Applications"
    hdiutil create -volname "Parla" -srcfolder "$staging" -ov -format UDZO "$DMG"
fi

echo "$DMG"
