#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$ROOT/scripts/macos/env.sh"

BUILD_DIR="${BUILD_DIR:-$ROOT/builddir-macos}"
APP_NAME="${APP_NAME:-Parla}"
APP_DIR="${APP_DIR:-$ROOT/dist/macos/$APP_NAME.app}"
BUNDLE_ID="${BUNDLE_ID:-io.github.trufae.Parla}"
VERSION="${VERSION:-$(awk -F"'" '/version:/ { print $2; exit }' "$ROOT/meson.build")}"

if [ ! -x "$BUILD_DIR/parla" ]; then
    "$ROOT/scripts/macos/build.sh"
fi

CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
FRAMEWORKS="$CONTENTS/Frameworks"

rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES" "$FRAMEWORKS"

cp "$BUILD_DIR/parla" "$MACOS/parla-bin"
chmod 755 "$MACOS/parla-bin"

cat > "$MACOS/parla" <<'EOF'
#!/bin/sh
APP_MACOS="$(cd "$(dirname "$0")" && pwd)"
APP_CONTENTS="$(cd "$APP_MACOS/.." && pwd)"
APP_RESOURCES="$APP_CONTENTS/Resources"

export XDG_DATA_DIRS="$APP_RESOURCES/share${XDG_DATA_DIRS:+:$XDG_DATA_DIRS}"
export GSETTINGS_SCHEMA_DIR="$APP_RESOURCES/share/glib-2.0/schemas"
export GTK_DATA_PREFIX="$APP_RESOURCES"
export GTK_EXE_PREFIX="$APP_CONTENTS"
export GTK_PATH="$APP_RESOURCES"
export GIO_EXTRA_MODULES="$APP_RESOURCES/lib/gio/modules"

PIXBUF_DIR="$APP_RESOURCES/lib/gdk-pixbuf-2.0/2.10.0/loaders"
PIXBUF_QUERY="$APP_RESOURCES/bin/gdk-pixbuf-query-loaders"
PIXBUF_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/Library/Caches}/Parla"
PIXBUF_CACHE="$PIXBUF_CACHE_DIR/gdk-pixbuf-loaders.cache"
if [ -d "$PIXBUF_DIR" ] && [ -x "$PIXBUF_QUERY" ]; then
    mkdir -p "$PIXBUF_CACHE_DIR"
    if [ ! -f "$PIXBUF_CACHE" ] || ! grep -q "$PIXBUF_DIR" "$PIXBUF_CACHE" 2>/dev/null; then
        "$PIXBUF_QUERY" "$PIXBUF_DIR"/*.so > "$PIXBUF_CACHE" 2>/dev/null || rm -f "$PIXBUF_CACHE"
    fi
    [ -f "$PIXBUF_CACHE" ] && export GDK_PIXBUF_MODULE_FILE="$PIXBUF_CACHE"
    export GDK_PIXBUF_MODULEDIR="$PIXBUF_DIR"
fi

exec "$APP_MACOS/parla-bin" "$@"
EOF
chmod 755 "$MACOS/parla"

cat > "$CONTENTS/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>parla</string>
  <key>CFBundleIconFile</key>
  <string>Parla</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Parla</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$VERSION</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSHumanReadableCopyright</key>
  <string>GPLv3</string>
</dict>
</plist>
EOF

copy_dir() {
    local src="$1"
    local dst="$2"
    [ -d "$src" ] || return 0
    mkdir -p "$dst"
    rsync -aL "$src/" "$dst/"
}

copy_file() {
    local src="$1"
    local dst="$2"
    [ -f "$src" ] || return 0
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
}

make_icon() {
    local iconset="$RESOURCES/Parla.iconset"
    local tmp="$RESOURCES/.icon.png"
    rm -rf "$iconset"
    mkdir -p "$iconset"

    if command -v rsvg-convert >/dev/null 2>&1; then
        rsvg-convert -w 1024 -h 1024 "$ROOT/parla.svg" -o "$tmp"
    else
        cp "$ROOT/parla.png" "$tmp"
    fi

    sips -z 16 16     "$tmp" --out "$iconset/icon_16x16.png" >/dev/null
    sips -z 32 32     "$tmp" --out "$iconset/icon_16x16@2x.png" >/dev/null
    sips -z 32 32     "$tmp" --out "$iconset/icon_32x32.png" >/dev/null
    sips -z 64 64     "$tmp" --out "$iconset/icon_32x32@2x.png" >/dev/null
    sips -z 128 128   "$tmp" --out "$iconset/icon_128x128.png" >/dev/null
    sips -z 256 256   "$tmp" --out "$iconset/icon_128x128@2x.png" >/dev/null
    sips -z 256 256   "$tmp" --out "$iconset/icon_256x256.png" >/dev/null
    sips -z 512 512   "$tmp" --out "$iconset/icon_256x256@2x.png" >/dev/null
    sips -z 512 512   "$tmp" --out "$iconset/icon_512x512.png" >/dev/null
    sips -z 1024 1024 "$tmp" --out "$iconset/icon_512x512@2x.png" >/dev/null
    iconutil -c icns "$iconset" -o "$RESOURCES/Parla.icns"
    rm -rf "$iconset" "$tmp"
}

copy_dir "$BREW_PREFIX/share/glib-2.0/schemas" "$RESOURCES/share/glib-2.0/schemas"
if command -v glib-compile-schemas >/dev/null 2>&1 && [ -d "$RESOURCES/share/glib-2.0/schemas" ]; then
    glib-compile-schemas "$RESOURCES/share/glib-2.0/schemas"
fi

copy_dir "$BREW_PREFIX/share/icons/Adwaita" "$RESOURCES/share/icons/Adwaita"
copy_dir "$BREW_PREFIX/share/icons/hicolor" "$RESOURCES/share/icons/hicolor"
copy_dir "$ROOT/data/icons" "$RESOURCES/share/icons"
copy_dir "$BREW_PREFIX/share/mime" "$RESOURCES/share/mime"
copy_dir "$BREW_PREFIX/share/themes" "$RESOURCES/share/themes"
copy_dir "$BREW_PREFIX/etc/fonts" "$RESOURCES/etc/fonts"

copy_file "$ROOT/data/io.github.trufae.Parla.appdata.xml" \
    "$RESOURCES/share/metainfo/io.github.trufae.Parla.metainfo.xml"
copy_file "$ROOT/data/io.github.trufae.Parla.desktop" \
    "$RESOURCES/share/applications/io.github.trufae.Parla.desktop"

copy_dir "$BREW_PREFIX/lib/gio/modules" "$RESOURCES/lib/gio/modules"
copy_dir "$BREW_PREFIX/lib/gdk-pixbuf-2.0" "$RESOURCES/lib/gdk-pixbuf-2.0"
copy_dir "$BREW_PREFIX/lib/gtk-4.0" "$RESOURCES/lib/gtk-4.0"
if command -v gdk-pixbuf-query-loaders >/dev/null 2>&1; then
    copy_file "$(command -v gdk-pixbuf-query-loaders)" "$RESOURCES/bin/gdk-pixbuf-query-loaders"
fi

rpc_server="${PARLA_BUNDLE_RPC_SERVER:-${PARLA_RPC_SERVER:-}}"
if [ -z "$rpc_server" ] && command -v deltachat-rpc-server >/dev/null 2>&1; then
    rpc_server="$(command -v deltachat-rpc-server)"
fi
if [ -n "$rpc_server" ] && [ -x "$rpc_server" ]; then
    cp "$rpc_server" "$MACOS/deltachat-rpc-server"
    chmod 755 "$MACOS/deltachat-rpc-server"
else
    echo "warning: deltachat-rpc-server not bundled; install it separately or set PARLA_BUNDLE_RPC_SERVER" >&2
fi

make_icon

is_macho() {
    file -b "$1" 2>/dev/null | grep -q 'Mach-O'
}

relative_to_frameworks() {
    python3 - "$1" "$FRAMEWORKS" <<'PY'
import os
import sys
print(os.path.relpath(sys.argv[2], sys.argv[1]))
PY
}

declare -A processed

bundle_macho() {
    local file="$1"
    [ -f "$file" ] || return 0
    is_macho "$file" || return 0

    local real
    real="$(cd "$(dirname "$file")" && pwd -P)/$(basename "$file")"
    if [ "${processed[$real]+set}" = set ]; then
        return 0
    fi
    processed[$real]=1

    chmod u+w "$file" 2>/dev/null || true

    local loader_dir rel dep base dest
    loader_dir="$(cd "$(dirname "$file")" && pwd -P)"
    rel="$(relative_to_frameworks "$loader_dir")"

    while IFS= read -r dep; do
        case "$dep" in
            "$BREW_PREFIX"/*|/usr/local/*)
                base="$(basename "$dep")"
                dest="$FRAMEWORKS/$base"
                if [ ! -f "$dest" ]; then
                    cp -L "$dep" "$dest"
                    chmod u+w "$dest"
                    install_name_tool -id "@rpath/$base" "$dest" 2>/dev/null || true
                fi
                install_name_tool -change "$dep" "@loader_path/$rel/$base" "$file" 2>/dev/null || true
                bundle_macho "$dest"
                ;;
        esac
    done < <(otool -L "$file" | awk 'NR > 1 { print $1 }')
}

while IFS= read -r -d '' file; do
    bundle_macho "$file"
done < <(find "$APP_DIR" -type f -print0)

if [ "${CODESIGN:-adhoc}" != "none" ] && command -v codesign >/dev/null 2>&1; then
    codesign --force --deep --sign "${CODESIGN_IDENTITY:--}" "$APP_DIR" >/dev/null 2>&1 || \
        echo "warning: codesign failed; leaving app unsigned" >&2
fi

echo "$APP_DIR"
