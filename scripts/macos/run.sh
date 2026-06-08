#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$ROOT/scripts/macos/env.sh"

BUILD_DIR="${BUILD_DIR:-$ROOT/builddir-macos}"
APP_NAME="${APP_NAME:-Parla}"
APP_DIR="${APP_DIR:-$ROOT/dist/macos/$APP_NAME.app}"
APP_BIN="$APP_DIR/Contents/MacOS/parla"

"$ROOT/scripts/macos/build.sh"

needs_bundle() {
    [ -x "$APP_BIN" ] || return 0
    [ "$BUILD_DIR/parla" -nt "$APP_BIN" ] && return 0
    [ "$ROOT/scripts/macos/bundle.sh" -nt "$APP_BIN" ] && return 0
    [ "$ROOT/meson.build" -nt "$APP_BIN" ] && return 0
    [ "$ROOT/parla.svg" -nt "$APP_BIN" ] && return 0
    [ "$ROOT/parla.png" -nt "$APP_BIN" ] && return 0
    [ "$ROOT/data/io.github.trufae.Parla.appdata.xml" -nt "$APP_BIN" ] && return 0
    [ "$ROOT/data/io.github.trufae.Parla.desktop" -nt "$APP_BIN" ] && return 0
    [ -n "$(find "$ROOT/data/icons" -type f -newer "$APP_BIN" -print -quit)" ] && return 0
    return 1
}

if needs_bundle; then
    APP_OUTPUT="$(PARLA_BUNDLE_CLEAN=0 "$ROOT/scripts/macos/bundle.sh")"
    APP_DIR="${APP_OUTPUT##*$'\n'}"
fi
exec open -n -W "$APP_DIR" --args "$@"
