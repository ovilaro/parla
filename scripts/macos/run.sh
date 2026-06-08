#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT/builddir-macos}"

"$ROOT/scripts/macos/build.sh"
exec "$BUILD_DIR/parla" "$@"
