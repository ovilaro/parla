#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$ROOT/scripts/macos/env.sh"

BUILD_DIR="${BUILD_DIR:-$ROOT/builddir-macos}"
BUILDTYPE="${BUILDTYPE:-release}"

if [ -f "$BUILD_DIR/build.ninja" ]; then
    meson setup --reconfigure "$BUILD_DIR" --buildtype="$BUILDTYPE" --prefix=/usr/local
else
    if [ -d "$BUILD_DIR" ]; then
        echo "Removing incomplete build directory: $BUILD_DIR"
        rm -rf "$BUILD_DIR"
    fi
    meson setup "$BUILD_DIR" "$ROOT" --buildtype="$BUILDTYPE" --prefix=/usr/local
fi

meson compile -C "$BUILD_DIR"
