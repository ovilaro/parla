DESTDIR ?=
PREFIX ?= /usr/local
BUILD_DIR ?= builddir
BUILDTYPE ?= debug
MESON_OPTIONS ?=
UNAME_S := $(shell uname -s)
RUN_ENV := $(if $(filter Darwin,$(UNAME_S)),. ../scripts/macos/env.sh &&,)

.PHONY: all run test clean install uninstall

all:
	$(RUN_ENV) if [ -f "$(BUILD_DIR)/build.ninja" ]; then \
		meson setup --reconfigure "$(BUILD_DIR)" . \
			--buildtype="$(BUILDTYPE)" --prefix="$(PREFIX)" $(MESON_OPTIONS); \
	else \
		meson setup "$(BUILD_DIR)" . \
			--buildtype="$(BUILDTYPE)" --prefix="$(PREFIX)" $(MESON_OPTIONS); \
	fi
	$(RUN_ENV) meson compile -C "$(BUILD_DIR)"

run: all
	$(RUN_ENV) "./$(BUILD_DIR)/safestore-gui"

cli: all
	$(RUN_ENV) "./$(BUILD_DIR)/safestore" --help

test: all
	$(RUN_ENV) meson test -C "$(BUILD_DIR)" --print-errorlogs

clean:
	if [ -f "$(BUILD_DIR)/build.ninja" ]; then \
		meson compile -C "$(BUILD_DIR)" --clean; \
	fi

install: all
	DESTDIR="$(DESTDIR)" meson install -C "$(BUILD_DIR)"

uninstall:
	rm -f "$(DESTDIR)$(PREFIX)/bin/safestore"
	rm -f "$(DESTDIR)$(PREFIX)/bin/safestore-gui"
	rm -f "$(DESTDIR)$(PREFIX)/share/applications/io.github.trufae.SafeStore.desktop"
