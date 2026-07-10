#!/usr/bin/env bash
# Build a self-contained Windows distribution of Parla and zip it.
#
# Must run inside an MSYS2 UCRT64 shell (in CI: msys2/setup-msys2@v2)
# with meson, valac, gtk4, libadwaita, json-glib, glib-networking,
# librsvg and ntldd installed. The bundling recipe follows how Tuba
# and Dino ship their Windows builds: meson install into a prefix,
# then copy the recursive DLL closure plus the GLib/GTK runtime data.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT/builddir-windows}"
BUILDTYPE="${BUILDTYPE:-release}"
VERSION="${VERSION:-$(awk -F"'" '/version:/ { print $2; exit }' "$ROOT/meson.build")}"
ARCH="${MSYSTEM_CARCH:-x86_64}"
PREFIX="${MINGW_PREFIX:-/ucrt64}"
DIST="$ROOT/dist/windows/parla"
ZIP="$ROOT/dist/windows/parla-$VERSION-windows-$ARCH.zip"

rm -rf "$DIST"
mkdir -p "$DIST"

# meson needs a native (mixed C:/...) path for the install prefix.
dist_prefix="$DIST"
if command -v cygpath >/dev/null; then
    dist_prefix="$(cygpath -m "$DIST")"
fi

if [ ! -d "$BUILD_DIR" ]; then
    meson setup "$BUILD_DIR" "$ROOT" --buildtype="$BUILDTYPE" --prefix="$dist_prefix"
fi
meson compile -C "$BUILD_DIR"
meson install -C "$BUILD_DIR"

BIN="$DIST/bin"

# Helper executables GLib spawns at runtime: gdbus.exe for the win32
# D-Bus autolaunch, gspawn-*.exe for GSubprocess (the rpc server and
# the external audio player are both spawned through it).
cp "$PREFIX/bin/gdbus.exe" \
   "$PREFIX/bin/gspawn-win64-helper.exe" \
   "$PREFIX/bin/gspawn-win64-helper-console.exe" \
   "$BIN/"

# gdk-pixbuf loaders; the librsvg loader renders the SVG icon themes.
# The loaders.cache MSYS2 ships is relocatable as long as the
# bin/../lib layout is preserved.
mkdir -p "$DIST/lib"
cp -r "$PREFIX/lib/gdk-pixbuf-2.0" "$DIST/lib/"

# GIO modules: libgiognutls provides TlsClientConnection, which the
# rpc-server download uses for HTTPS. Without it TLS just "is not
# available" at runtime.
mkdir -p "$DIST/lib/gio"
cp -r "$PREFIX/lib/gio/modules" "$DIST/lib/gio/"
find "$DIST/lib" -name '*.a' -delete

# Recursive DLL closure over everything shipped so far. ntldd -R
# prints "name.dll => C:\...\ucrt64\bin\name.dll" lines; DLLs from
# Windows itself do not match the prefix filter and stay external.
find "$DIST" \( -iname '*.exe' -o -iname '*.dll' \) -print0 \
    | xargs -0 ntldd -R \
    | grep -iF "$(basename "$PREFIX")" \
    | awk '{ print $1 }' \
    | sort -u \
    | while IFS= read -r dll; do
        if [ -f "$PREFIX/bin/$dll" ]; then
            cp "$PREFIX/bin/$dll" "$BIN/"
        fi
    done

# GSettings schemas: GTK aborts on startup paths that touch
# org.gtk.gtk4.Settings.* when the compiled schemas are missing.
mkdir -p "$DIST/share/glib-2.0/schemas"
cp "$PREFIX"/share/glib-2.0/schemas/*.xml "$DIST/share/glib-2.0/schemas/"
glib-compile-schemas "$DIST/share/glib-2.0/schemas"
rm -f "$DIST/share/glib-2.0/schemas"/*.xml

# Icon themes: Adwaita for the stock symbolic icons; hicolor already
# holds the app icons that meson install placed there, it only lacks
# the theme index.
mkdir -p "$DIST/share/icons"
cp -r "$PREFIX/share/icons/Adwaita" "$DIST/share/icons/"
cp "$PREFIX/share/icons/hicolor/index.theme" "$DIST/share/icons/hicolor/"
for theme in Adwaita hicolor; do
    gtk4-update-icon-cache -f -t "$DIST/share/icons/$theme" 2>/dev/null \
        || gtk-update-icon-cache -f -t "$DIST/share/icons/$theme" \
        || true
done

# Fontconfig configuration; pango's win32 backend reads it when present.
if [ -d "$PREFIX/etc/fonts" ]; then
    mkdir -p "$DIST/etc"
    cp -r "$PREFIX/etc/fonts" "$DIST/etc/"
fi

find "$DIST" \( -iname '*.exe' -o -iname '*.dll' \) -exec strip -s {} + 2>/dev/null || true

rm -f "$ZIP"
(cd "$(dirname "$DIST")" && zip -r -9 -q "$ZIP" "$(basename "$DIST")")
echo "$ZIP"
