DESTDIR?=
PREFIX?=/usr/local
BINDIR?=$(PREFIX)/bin
DATADIR?=$(PREFIX)/share
BUILD_DIR?=builddir
BUILDTYPE?=debug
UNAME_S := $(shell uname -s)
RUN_ENV := $(if $(filter Darwin,$(UNAME_S)),. ./scripts/macos/env.sh &&,)
MACOS_APP_DIR?=dist/macos/Parla.app
MESON_OPTIONS?=

ifeq ($(UNAME_S),Darwin)
MACOS_CLIPBOARD_WORKAROUND?=true
MESON_OPTIONS += -Dmacos_clipboard_workaround=$(MACOS_CLIPBOARD_WORKAROUND)
endif

.PHONY: all asan run clean install uninstall deb app dmg appimage

all:
	$(RUN_ENV) if [ -f "$(BUILD_DIR)/build.ninja" ]; then meson setup --reconfigure "$(BUILD_DIR)" --buildtype="$(BUILDTYPE)" --prefix="$(PREFIX)" $(MESON_OPTIONS); else meson setup "$(BUILD_DIR)" . --buildtype="$(BUILDTYPE)" --prefix="$(PREFIX)" $(MESON_OPTIONS); fi
	$(RUN_ENV) meson compile -C "$(BUILD_DIR)"

asan: BUILD_DIR=builddir-asan
asan: BUILDTYPE=debug
asan: MESON_OPTIONS += -Db_sanitize=address -Dstrip=false -Dvala_args=--debug -Dc_args=-g
asan: all

ifeq ($(UNAME_S),Darwin)
run: all
	BUILD_DIR="$(BUILD_DIR)" APP_DIR="$(CURDIR)/$(MACOS_APP_DIR)" PARLA_BUNDLE_CLEAN=0 bash scripts/macos/bundle.sh >/dev/null
	open -n -W "$(CURDIR)/$(MACOS_APP_DIR)"
else
run: all
	$(RUN_ENV) "./$(BUILD_DIR)/parla"
endif

clean:
	rm -rf builddir builddir-asan dist/macos

install: all
	DESTDIR="$(DESTDIR)" meson install -C "$(BUILD_DIR)"

uninstall:
	rm -f "$(DESTDIR)$(BINDIR)/parla"
	rm -f "$(DESTDIR)$(DATADIR)/applications/io.github.trufae.Parla.desktop"
	rm -f "$(DESTDIR)$(DATADIR)/icons/hicolor/scalable/apps/io.github.trufae.Parla.svg"
	rm -f "$(DESTDIR)$(DATADIR)/icons/hicolor/scalable/apps/parla-welcome.svg"
	rm -f "$(DESTDIR)$(DATADIR)/icons/hicolor/scalable/apps/parla-tray.svg"
	rm -f "$(DESTDIR)$(DATADIR)/metainfo/io.github.trufae.Parla.metainfo.xml"
	-gtk-update-icon-cache -f -t $(DESTDIR)$(DATADIR)/icons/hicolor 2>/dev/null
	-update-desktop-database $(DESTDIR)$(DATADIR)/applications 2>/dev/null

deb: all
	$(MAKE) -C dist/debian

app: all
	BUILD_DIR="$(BUILD_DIR)" bash scripts/macos/bundle.sh

dmg: BUILDTYPE=release
dmg:
	BUILD_DIR="$(BUILD_DIR)" BUILDTYPE="$(BUILDTYPE)" bash scripts/macos/package-dmg.sh

appimage: BUILD_DIR=builddir-appimage
appimage: BUILDTYPE=release
appimage:
	BUILD_DIR="$(BUILD_DIR)" BUILDTYPE="$(BUILDTYPE)" bash dist/appimage/build.sh
