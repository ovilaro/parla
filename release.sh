#!/bin/sh
set -e

ROOT="$(cd "$(dirname "$0")" && pwd)"
ARTIFACT_DIR="${ARTIFACT_DIR:-$ROOT/dist/release}"

rm -rf "$ARTIFACT_DIR"
mkdir -p "$ARTIFACT_DIR"

make -C "$ROOT" appimage
cp "$ROOT"/dist/appimage/out/*.AppImage "$ARTIFACT_DIR"/

if [ "$(uname -s)" = Darwin ]; then
    make -C "$ROOT" dmg
    cp "$ROOT"/dist/macos/*.dmg "$ARTIFACT_DIR"/
fi

echo "Release artifacts:"
find "$ARTIFACT_DIR" -maxdepth 1 -type f -print | sort
