DESTDIR?=
PREFIX?=/usr/local
BINDIR?=$(PREFIX)/bin
DATADIR?=$(PREFIX)/share
UNAME_S := $(shell uname -s)
BUILD_DIR ?= $(if $(filter Darwin,$(UNAME_S)),builddir-macos,builddir)

all:
	./build.sh

run: all
	./$(BUILD_DIR)/parla

clean:
	rm -rf builddir builddir-macos dist/macos

install:
	install -Dm755 ./$(BUILD_DIR)/parla $(DESTDIR)$(BINDIR)/parla
	install -Dm644 data/io.github.trufae.Parla.desktop $(DESTDIR)$(DATADIR)/applications/io.github.trufae.Parla.desktop
	install -Dm644 data/icons/hicolor/scalable/apps/io.github.trufae.Parla.svg $(DESTDIR)$(DATADIR)/icons/hicolor/scalable/apps/io.github.trufae.Parla.svg
	install -Dm644 data/io.github.trufae.Parla.appdata.xml $(DESTDIR)$(DATADIR)/metainfo/io.github.trufae.Parla.metainfo.xml
	-gtk-update-icon-cache -f -t $(DESTDIR)$(DATADIR)/icons/hicolor 2>/dev/null
	-update-desktop-database $(DESTDIR)$(DATADIR)/applications 2>/dev/null

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/parla
	rm -f $(DESTDIR)$(DATADIR)/applications/io.github.trufae.Parla.desktop
	rm -f $(DESTDIR)$(DATADIR)/icons/hicolor/scalable/apps/io.github.trufae.Parla.svg
	rm -f $(DESTDIR)$(DATADIR)/metainfo/io.github.trufae.Parla.metainfo.xml
	-gtk-update-icon-cache -f -t $(DESTDIR)$(DATADIR)/icons/hicolor 2>/dev/null
	-update-desktop-database $(DESTDIR)$(DATADIR)/applications 2>/dev/null

deb: all
	$(MAKE) -C dist/debian

macos:
	scripts/macos/build.sh

macos-run:
	scripts/macos/run.sh

macos-app:
	scripts/macos/bundle.sh

macos-dmg:
	scripts/macos/package-dmg.sh
