#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$ROOT/scripts/macos/env.sh"

APP_OUTPUT="$("$ROOT/scripts/macos/bundle.sh")"
APP_DIR="${APP_OUTPUT##*$'\n'}"
exec open -n -W "$APP_DIR" --args "$@"
