# AppImage

Build a Linux AppImage from the repository root:

```sh
make appimage
```

The build writes:

- `dist/appimage/AppDir`
- `dist/appimage/out/Parla-<version>-<arch>.AppImage`
- downloaded packaging tools under `dist/appimage/tools`

By default the script bundles `deltachat-rpc-server` from `PATH`; if it is not
installed locally, it downloads the pinned release asset from the Flatpak
manifest and verifies its SHA-256 checksum.

Useful overrides:

```sh
PARLA_APPIMAGE_RPC_SERVER=/path/to/deltachat-rpc-server make appimage
ARCH=x86_64 make appimage
PARLA_APPIMAGE_GTK_PLUGIN=0 make appimage
```
