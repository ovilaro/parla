# SafeStore

SafeStore manages local encrypted [CryFS](https://www.cryfs.org/) vaults. It
was built to exercise the encrypted-storage workflow before integrating it
into Parla: the mounted plaintext path is what Parla will later hand to
`deltachat-rpc-server` as `DC_ACCOUNTS_PATH`.

It is split into three parts:

- `lib/` — a GTK-free core library (`libsafestore-core`) with the vault,
  path-policy, mount-detection, and keyring logic. This is the piece Parla
  links against.
- `cli/` — the `safestore` command-line tool for scripted and automated use.
- `gui/` — the `safestore-gui` GTK4/libadwaita application.

## What it does

- Creates a new CryFS vault using XChaCha20-Poly1305.
- Unlocks an existing vault after checking for `cryfs.config`.
- Detects vault state from the platform mount table, distinguishing an
  encrypted vault, the decrypted view of a mounted vault
  (`cryfs@<vault>` on `fuse.cryfs`), and a plain directory.
- Refuses to run when CryFS is not installed, before asking for a password.
- Sends the password to CryFS through a private stdin pipe. It is never
  placed in command-line arguments, environment variables, settings, or
  the activity log.
- Optionally remembers vault passwords in the operating system's secret
  store (Secret Service via libsecret on Linux, the login keychain on
  macOS), never in a plain file on disk. Windows has no keyring backend
  yet and always prompts.
- Verifies that the mount actually appears instead of trusting console
  text, and locks with the strict `cryfs-unmount --immediate` path.
- Supports CryFS idle unmounting.
- Rejects nested vault/mount paths and non-empty mount directories.
- Stores only paths and the idle-lock preference.

## Requirements

Build requirements: Vala 0.56+, Meson/Ninja, GLib/GIO; GTK 4 and
libadwaita 1.5+ for the GUI; libsecret (optional) for the Linux keyring.

Runtime requirements:

- **CryFS stable 1.x**, preferably 1.0.3, including `cryfs` and
  `cryfs-unmount`. Distribution packages such as Ubuntu's 0.11.4 work for
  experimentation (same CLI, XChaCha20 since 0.11.0), but releases should
  pin and verify an exact 1.x version. CryFS 2.0 is an alpha with a
  different CLI story and must not be used.
- Linux: FUSE.
- macOS: macFUSE plus permission to load its system extension. Homebrew's
  core `cryfs` formula is Linux-only; use the
  [official CryFS tap](https://github.com/cryfs/homebrew-tap)
  (`brew install --cask macfuse && brew install cryfs/tap/cryfs`) or
  MacPorts (`sudo port install cryfs`).
- Windows (experimental upstream): the CryFS 1.x Windows package, Dokany
  2.2.0.1000, and the MSVC 2022 runtime. Stable CryFS 1.x mounts on an
  unused drive letter such as `G:`, not an arbitrary directory.

## Build and run

From this directory:

```sh
make test
make run
```

`make run` configures Meson when needed, compiles SafeStore, and starts the
GUI (`safestore-gui`). The CLI is built alongside it as
`builddir/safestore`.

Other useful targets:

```sh
make                 # build
make test            # build and run tests
make clean           # clean compiled outputs
make install         # install under PREFIX, default /usr/local
make install PREFIX="$HOME/.local"
```

On macOS the Makefile reuses Parla's Homebrew GTK environment helper. On
Windows, build from an MSYS2 UCRT64 shell.

A nonstandard CryFS installation can be selected with
`SAFESTORE_CRYFS=/absolute/path/to/cryfs` or `--binary`; the same directory
must also contain `cryfs-unmount`.

## Command line

The `safestore` tool covers the whole lifecycle without the GUI:

```sh
safestore check ~/.vault            # encrypted vault, decrypted mount, or neither?
safestore status ~/.vault ~/plain   # vault + mount state
safestore create ~/.vault ~/plain   # new vault, prompts for a password twice
safestore mount ~/.vault ~/plain    # unlock; prompts without echoing
safestore umount ~/plain            # lock again
```

Exit codes are script-friendly: `0` yes/success, `1` no/failure, `2` usage
error; `check` additionally returns `3` when the path is the decrypted view
of a mounted CryFS vault. Paths omitted on the command line default to the
settings file shared with the GUI, so a configured setup reduces to
`safestore mount` and `safestore umount`.

Passwords are never accepted as command-line arguments. The sources are:

- an interactive prompt with terminal echo disabled (the default),
- `--password-stdin` for scripts and other programs,
- `--keyring` to fetch the password from the OS secret store. On the first
  interactive unlock with `--keyring`, the password is saved there after a
  successful mount; `safestore forget` removes it again. Combined with the
  keyring, `safestore mount` needs no interaction at all, which is the
  intended path toward automatic unlocking from Parla.

Unlike the GUI, the CLI lets CryFS daemonize itself, so mounts survive the
CLI exiting; `safestore umount` (or CryFS idle unmounting via `--idle`)
locks the vault.

## Using the GUI

1. Choose an **encrypted vault folder**. This is the on-disk ciphertext.
2. Choose a separate **plaintext mount folder**. It must be empty. On
   Windows, enter an unused drive letter such as `G:`.
3. For a new empty vault, press **Create** and enter the password twice.
4. For a vault containing `cryfs.config`, press **Unlock**.
5. Work only through the mounted path.
6. Close every application using the mount and press **Lock** before
   exiting.

The GUI runs CryFS in the foreground, watches the process, and deliberately
refuses to close while its CryFS child is active; force-killing during
writes can damage the vault. The **Copy Accounts Path** button copies the
mounted path for manual `DC_ACCOUNTS_PATH` experiments.

## Stored state

Non-secret preferences go to `$XDG_CONFIG_HOME/safestore/settings.ini` (or
the platform's GLib equivalent). CryFS rollback/integrity state is kept
under `safestore/cryfs-state/` in the GLib user-data directory.

The password is not saved to disk by SafeStore itself. With `--keyring` it
is handed to the operating system's secret store, which keeps it encrypted
under the user's login session. GTK, GLib, the operating system, and CryFS
will necessarily hold password/key material in process memory while
unlocking or using the filesystem; this prototype cannot guarantee locked
or zeroized memory.

## Security model

CryFS encrypts file contents, names, sizes, metadata, and directory
structure; only encrypted blocks persist in the vault directory. This
protects **data at rest**: a clean lock, shutdown, stolen powered-off disk,
or a copied/synced vault directory, with modification detection through
CryFS authenticated encryption and local state.

It does **not** protect against malware or an attacker on the unlocked
machine, memory/swap/hibernation extraction, files copied out of the
mounted view, or plaintext that applications spill outside the mount
(caches, thumbnails, logs, crash dumps). User-facing wording must say
"encrypted account storage at rest," never "no plaintext anywhere."

Rules that must hold in any integration:

- Passwords never enter argv, environment variables, settings, or logs.
- Creation and unlock are separate actions; unlock never silently creates
  a vault at a typoed path.
- Never automatically pass `--allow-filesystem-upgrade`,
  `--allow-replaced-filesystem`, or `--allow-integrity-violations`. Those
  belong in an explicit recovery workflow after a backup. CryFS exit codes
  distinguish wrong passwords, format issues, and integrity violations;
  keep those distinctions in the UI.
- No home-grown cryptography: CryFS derives and wraps its own keys. A
  future "password plus recovery code" envelope is a new cryptographic
  format and needs independent review before it exists.

## Important safety rules

- Keep backups of the complete encrypted vault, including `cryfs.config`.
- Only sync the encrypted vault — never the plaintext mount — and never
  mount the same synced vault on two machines at once. Lock first and let
  sync finish before unlocking elsewhere.
- A forgotten password means lost data unless it is stored in the keyring
  or a password manager; there is no recovery system.
- Test with disposable data first.

## Parla integration plan

The integration point is before `deltachat-rpc-server` starts:

1. Resolve the configured vault and mount locations.
2. Detect whether the expected CryFS filesystem is already mounted (mount
   identity, not directory existence).
3. Unlock via keyring, or prompt only in an interactive session.
4. Wait for verified mount readiness, then start the RPC server with
   `DC_ACCOUNTS_PATH` set to the mounted path.
5. On lock/quit: stop UI writes, shut the RPC server down and wait for it,
   strictly unmount, verify disappearance, and only then report locked.

Migration must copy — not move — the existing accounts directory into a
freshly verified vault, validate everything, and keep the plaintext backup
until an encrypted backup has passed a restore test.

Remaining work before this is a supported Parla feature:

- Windows: a Credential Manager keyring backend and mount detection via
  volume APIs (a drive letter existing proves nothing today).
- Pin and verify an exact CryFS 1.x version; decide bundled vs. system
  packaging, and reject unsupported versions instead of just showing them.
- A single-instance owner/lock so two Parla instances cannot race for the
  vault, plus the edge cases: RPC startup failure after mount, mount
  disappearing while running, busy files at shutdown, short shutdown grace
  periods.
- Plaintext-footprint audit (Delta Chat WAL/blobs, thumbnails, search
  indexes, crash dumps) — move controllable caches into the mount.
- Real-hardware testing on macOS (keychain backend, macFUSE approval) and
  Windows; power-loss and crash tests at controlled write points.
- A documented backup/recovery procedure users can perform without Parla.

## Project layout

```text
safestore/
├── data/               desktop launcher
├── lib/                core library: vault, keyring, path and mount logic
├── cli/                safestore command-line tool
├── gui/                safestore-gui GTK application
├── tests/              path/layout safety tests
├── Makefile            build/run/test convenience targets
├── meson.build         standalone Meson project
└── README.md           this guide
```

## References

- [CryFS tutorial](https://www.cryfs.org/tutorial) and
  [design](https://www.cryfs.org/howitworks)
- [CryFS stable releases](https://github.com/cryfs/cryfs/releases)
- [gocryptfs](https://github.com/rfjakob/gocryptfs) (possible alternative
  Linux backend; rclone crypt and EncFS were evaluated and rejected)
