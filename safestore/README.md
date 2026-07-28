# SafeStore

SafeStore is a standalone Vala/GTK experiment for creating, mounting, and
unmounting local [CryFS](https://www.cryfs.org/) vaults. It exists to let us
exercise the encrypted-storage workflow before integrating it into Parla.

It does **not** import, link to, or change Parla. The only connection is that
the mounted path can later be used as `DC_ACCOUNTS_PATH`.

## What it does

- Creates a new CryFS vault using XChaCha20-Poly1305.
- Unlocks an existing vault after checking for `cryfs.config`.
- Sends the password to CryFS through a private stdin pipe. It is never placed
  in command-line arguments, environment variables, settings, or the activity
  log.
- Runs CryFS in the foreground and watches the process.
- Verifies that the mount actually appears instead of trusting console text.
- Locks with the strict `cryfs-unmount --immediate` path, which refuses to
  hide a still-busy mount on Linux.
- Supports CryFS idle unmounting.
- Rejects nested vault/mount paths and non-empty mount directories.
- Stores only paths and the idle-lock preference.

This is an experiment, not yet a production security boundary. Read
[NOTES.md](NOTES.md) before trusting it with important data.

## Requirements

Build requirements:

- Vala 0.56 or newer
- Meson and Ninja
- GTK 4
- libadwaita 1.5 or newer
- GLib/GIO development files

Runtime requirements:

- **CryFS stable 1.x**, preferably 1.0.3, including `cryfs` and
  `cryfs-unmount`
- Linux: FUSE
- macOS: macFUSE plus permission to load its system extension
- Windows: the CryFS 1.x Windows package, Dokany 2.2.0.1000 as required by the
  stable package, and the Microsoft Visual C++ 2022 runtime

CryFS 2.0 is currently an alpha with a different support/CLI story. SafeStore
targets stable CryFS 1.x and should not be used with the alpha.

### Installing CryFS on macOS

Homebrew's core `cryfs` formula is deprecated and now supports Linux only. On
macOS, install stable CryFS 1.x from the
[official CryFS Homebrew tap](https://github.com/cryfs/homebrew-tap) together
with macFUSE:

```sh
brew install --cask macfuse
brew install cryfs/tap/cryfs
```

macOS may require you to approve the macFUSE system extension in **System
Settings → Privacy & Security** and restart the machine. Verify that both
executables required by SafeStore are available:

```sh
cryfs --version
cryfs-unmount --help
```

Alternatively, [MacPorts packages CryFS](https://ports.macports.org/port/cryfs/):

```sh
sudo port install cryfs
```

The official CryFS documentation describes Windows support as experimental.
Stable CryFS 1.x mounts a Windows vault on an unused drive letter such as
`G:`, not an arbitrary directory. Type that drive letter directly into the
mount field.

## Build and run

From this directory:

```sh
make test
make run
```

`make run` configures Meson when needed, compiles SafeStore, and starts it.

Other useful targets:

```sh
make                 # build
make test            # build and run tests
make clean           # clean compiled outputs
make install         # install under PREFIX, default /usr/local
make install PREFIX="$HOME/.local"
```

On macOS the Makefile reuses Parla's Homebrew GTK environment helper. On
Windows, build from an MSYS2 UCRT64 shell with the corresponding Vala, GTK,
libadwaita, Meson, and Ninja packages installed.

You may point the initial executable field at a nonstandard CryFS installation:

```sh
SAFESTORE_CRYFS=/absolute/path/to/cryfs make run
```

The same directory must also contain `cryfs-unmount` (or
`cryfs-unmount.exe`).

## Using it

1. Choose an **encrypted vault folder**. This is the on-disk ciphertext.
2. Choose a separate **plaintext mount folder**. It must be empty. On Windows,
   enter an unused drive letter such as `G:`.
3. For a new empty vault, press **Create** and enter the password twice.
4. For a vault containing `cryfs.config`, press **Unlock**.
5. Work only through the mounted path.
6. Close every application using the mount and press **Lock** before exiting.

SafeStore deliberately refuses to close while its CryFS child is active. It
does not force-kill CryFS because interruption during writes can damage the
vault.

The **Copy Accounts Path** button copies only the mounted path. For manual
experiments with Delta Chat:

```sh
DC_ACCOUNTS_PATH="/absolute/plaintext/mount" deltachat-rpc-server
```

Stop `deltachat-rpc-server` and wait for it to exit before locking the vault.
SafeStore does not enforce that relationship yet.

## Stored state

SafeStore writes non-secret preferences to:

```text
$XDG_CONFIG_HOME/safestore/settings.ini
```

or the platform's GLib user-config equivalent. CryFS rollback/integrity state
is kept in the platform's GLib user-data directory under:

```text
safestore/cryfs-state/
```

The password is not saved. GTK, GLib, the operating system, and CryFS will
necessarily hold password/key material in process memory while unlocking or
using the filesystem; this prototype cannot guarantee locked or zeroized
memory.

## Important safety rules

- Keep backups. Back up the complete encrypted vault, including
  `cryfs.config`.
- Never put the plaintext mount inside Dropbox, iCloud, OneDrive, Syncthing,
  or another sync root. Only sync the encrypted vault.
- Never mount the same synced vault on two machines at once.
- Lock on the first machine and let encrypted-file synchronization finish
  before unlocking elsewhere.
- A forgotten password currently means lost data. There is no QR/recovery
  system in this prototype.
- Do not enable CryFS integrity-bypass or filesystem-replacement flags just to
  make an error disappear. Investigate and restore from a known-good backup.
- Test with disposable data first.

## Project layout

```text
safestore/
├── data/               desktop launcher
├── src/                Vala application and CryFS controller
├── tests/              path/layout safety tests
├── Makefile            build/run/test convenience targets
├── meson.build         standalone Meson project
├── README.md            usage and safety guide
└── NOTES.md             production-readiness roadmap
```
