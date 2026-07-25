# SafeStore production roadmap

This document records what the experiment proves, what remains unsafe or
unverified, and the work required before encrypted account storage can become
a supported Parla feature.

## Current decision

CryFS is the primary experimental backend because it encrypts file contents,
names, sizes, metadata, and directory structure. The live filesystem remains
usable through normal file APIs, while only encrypted blocks persist in the
vault directory.

SafeStore targets **stable CryFS 1.x, preferably 1.0.3**. CryFS 2.0 is still an
alpha, is not a drop-in CLI replacement, and must be evaluated separately when
it becomes stable.

The other evaluated choices remain useful context:

| Backend | Position |
| --- | --- |
| CryFS | Primary experiment; best metadata-hiding model |
| gocryptfs | Strong optional Linux backend, but macOS is beta and Windows uses a separate implementation |
| rclone crypt | Suitable for encrypted sync/backup, not the preferred live local vault because VFS caches can create plaintext disk artifacts |
| EncFS | Rejected because of its old design and security-audit history |

We should keep the UI/backend boundary narrow enough that another audited
backend can be added later without changing Parla's account-storage contract.

## Threat model

The intended protection is:

- Data at rest after a clean lock, logout, shutdown, or stolen powered-off
  disk.
- A copied or remotely synchronized vault directory.
- Filenames, file sizes, metadata, and directory topology in that vault.
- Accidental access to the ciphertext directory without the unlock secret.
- Modification detection provided by CryFS authenticated encryption and local
  state.

This design does **not** protect against:

- Malware, a hostile administrator, debugger, or keylogger on an unlocked
  machine.
- Cold-boot, swap, hibernation, crash-dump, or process-memory extraction
  without additional OS hardening.
- Files copied by another program from the mounted view.
- Plaintext written by applications to caches, thumbnails, temporary files,
  backups, logs, search indexes, or crash reports outside the mount.
- An attacker who has both the vault and its password/recovery secret.
- Destructive corruption without independent backups.
- Traffic analysis showing that the encrypted vault exists and when blocks
  change.

Before marketing this feature, the user-facing wording must say “encrypted
account storage at rest,” not “the application leaves no plaintext anywhere.”

## Prototype architecture

The experiment owns this lifecycle:

```text
Locked
  └─ create/unlock + password over stdin
       └─ Starting
            ├─ native mount appears ──> Mounted
            │                            └─ strict unmount ──> Locking ──> Locked
            └─ process/mount failure ──> Error ──> cleanup with Lock
```

Important implemented constraints:

- Passwords never enter argv, environment variables, settings, or logs.
- CryFS runs with `CRYFS_FRONTEND=noninteractive`.
- Update checks are disabled for deterministic, offline startup.
- A private, stable `CRYFS_LOCAL_STATE_DIR` preserves CryFS rollback and
  replacement detection.
- Creation and unlock are separate actions. Unlock will not silently create a
  vault at a typoed path.
- Vault and mount directories cannot contain one another.
- The plaintext mount must be empty before use.
- Mount success is checked against native mount state.
- Lock uses `cryfs-unmount --immediate` and waits for the owned CryFS process.
- The app does not force-kill CryFS.

## Critical work before Parla integration

### 1. Backend/version contract

- Pin and test an exact stable CryFS version and on-disk format.
- Reject unsupported or alpha major versions in the UI rather than merely
  showing their version.
- Decide whether CryFS is bundled, downloaded, or supplied by the operating
  system.
- Verify upstream release signatures and publish hashes/SBOM data.
- Track CryFS and driver security advisories.
- Confirm LGPL obligations for every packaging model.
- Add a machine-readable helper/protocol if parsing or timing around the CLI
  becomes fragile. Do not parse localized human output.

### 2. Platform support

Linux:

- Test FUSE 2 and FUSE 3 distributions, AppArmor, SELinux, Flatpak, Snap, and
  user namespaces.
- Decide how a sandboxed Parla receives FUSE/device/mount permissions.
- Exercise suspend, logout, session shutdown, low disk space, and busy mounts.
- Validate `/proc/self/mountinfo` parsing for spaces, Unicode, bind mounts, and
  unusual filesystems.

macOS:

- Test Intel and Apple Silicon on each supported macOS release.
- Package or clearly install macFUSE; handle system-extension approval and
  required restarts.
- Verify mount detection for spaces, Unicode normalization, volumes, and
  relocated home directories.
- Decide code-signing, notarization, hardened-runtime, and helper-process
  architecture.
- Test sleep, Fast User Switching, logout, and abrupt app termination.

Windows:

- Treat support as experimental until the upstream CryFS Windows path passes a
  sustained test matrix.
- Stable CryFS 1.x requires an unused drive letter and a compatible Dokany
  runtime. Confirm and pin the exact supported Dokany build.
- Bundle the MSVC runtime and correctly signed filesystem driver, or provide a
  verified installer flow.
- Replace or prove GLib subprocess pipe handling for a GUI-subsystem parent.
- Detect mount state through Windows volume APIs rather than directory
  existence alone.
- Handle UAC boundaries, sessions, services, drive-letter races, antivirus,
  long paths, ACLs, case folding, and reboot cleanup.
- Decide what `DC_ACCOUNTS_PATH` should point to beneath the mounted drive.

No platform should be called supported until creation, unlock, random I/O,
consumer shutdown, lock, crash recovery, and upgrade tests pass on real
machines.

### 3. Parla lifecycle

The eventual integration point is before `deltachat-rpc-server` starts:

1. Resolve configured encrypted vault and mount locations.
2. Detect whether the expected CryFS filesystem is already mounted.
3. Prompt for unlock only in an interactive user session.
4. Wait for verified mount readiness.
5. Start the RPC server with `DC_ACCOUNTS_PATH` set to the mounted path.
6. On lock/quit, stop accepting UI writes.
7. Ask the RPC server to shut down and wait for process/file closure.
8. Strictly unmount and verify disappearance.
9. Only then report the account store as locked.

Required edge cases:

- RPC startup fails after a successful mount.
- User cancels unlock.
- Wrong password and retry throttling.
- Mount disappears while RPC is running.
- RPC refuses to exit or retains an open file.
- System shutdown supplies only a short grace period.
- Two Parla instances race to own the vault.
- The vault is already mounted by another process.
- The configured mount belongs to a different filesystem.
- Account migration runs out of space halfway through.

Use a single-instance owner/lock file plus native mount identity checks. A
directory merely existing is not proof that the correct vault is mounted.

### 4. Password and key handling

For the initial supported feature:

- Recommend a password-manager-generated secret or a long unique passphrase.
- Add strength feedback based on estimated entropy and known-password checks;
  length alone is insufficient.
- Keep clipboard use opt-in and automatically clear a copied generated secret
  where the platform permits.
- Disable screenshots where supported during secret display.
- Prevent secrets from reaching accessibility names, diagnostic logs, crash
  reports, shell history, argv, and environment blocks.
- Audit Vala/GTK/GLib allocations. Clearing a widget does not prove every copy
  was zeroized.
- Investigate locked memory and no-dump process settings, balanced against
  portability and sandboxing.
- Document OS swap, hibernation, and crash-dump hardening.

CryFS 1.x derives and wraps its encryption key using its own format. SafeStore
must not introduce home-grown encryption or silently transform passwords.

### 5. Recovery and QR design

The prototype intentionally has no recovery feature. CryFS does not expose a
ready-made, audited multiple-key-slot recovery system comparable to LUKS.

Safe baseline:

- Back up the entire ciphertext vault including `cryfs.config`.
- Store the unique password/recovery secret in a reputable password manager
  and optionally on printed paper in a physically secure place.
- Verify recovery on a second disposable machine before relying on it.

Potential future UX:

- Generate a high-entropy random vault secret.
- Show it once as text plus a QR code for offline transfer.
- Put a format/version identifier and checksum in the recovery payload so
  scanning errors are detected.
- Require an explicit “I stored this safely” verification step.
- Warn that phone photo backups, screenshot sync, chat apps, and printer
  spools can leak QR material.
- Never send recovery material through Parla itself by default.

A more convenient “password plus independent recovery code” would require
SafeStore to store the random CryFS password inside a separately encrypted
envelope with multiple unlock slots. That becomes a new cryptographic file
format and key-management subsystem. It requires:

- A written design and threat model.
- Established AEAD and memory-hard password KDF primitives.
- Format versioning and authenticated parameters.
- Atomic key-slot updates and rollback protection.
- Independent cryptographic review and fuzzing.
- A standalone recovery tool that does not depend on Parla.

Do not ship this envelope merely because library APIs make it easy to code.

### 6. “Post-quantum” wording

CryFS uses modern 256-bit symmetric authenticated encryption. Large symmetric
keys are generally the relevant conservative choice for data-at-rest security
against known quantum search techniques. The real practical risks here are
weak passwords, endpoint compromise, plaintext spill, implementation bugs, and
recovery failure.

ML-KEM or another public-key post-quantum mechanism is not needed merely to
encrypt a local single-user vault. It becomes relevant only if we design
recipient-based key sharing or recovery across devices. Any future claim must
name the exact security property and avoid the vague label “quantum proof.”

### 7. Sync and multi-device behavior

CryFS has no separate “sync now” command. Reads, writes, and `fsync` go through
the mounted filesystem; a third-party tool synchronizes encrypted blocks.

Production rules:

- Only the encrypted vault belongs in a cloud/sync folder.
- Never sync the plaintext mount.
- Never mount the same vault concurrently on multiple devices.
- Lock first, then wait for the sync provider to finish before unlocking
  elsewhere.
- Surface sync-provider status only through an explicit adapter; do not infer
  completion from elapsed time.
- Test conflict files, partial downloads, remote rollback, missing blocks, and
  malicious modifications.
- Backups must be versioned and independently restorable, not just mirrored
  deletions.

### 8. Integrity and recovery errors

CryFS exit codes distinguish wrong passwords, unsupported formats, replaced
filesystems, changed keys, and integrity violations. Keep these distinctions
in the UI.

Never automatically add:

- `--allow-filesystem-upgrade`
- `--allow-replaced-filesystem`
- `--allow-integrity-violations`

Those options belong in an explicit recovery workflow after backup and user
confirmation. Upgrades should copy or snapshot the encrypted vault first and
offer rollback instructions.

### 9. Plaintext-footprint audit

Before release, trace actual filesystem writes while Parla is unlocked:

- Delta Chat databases, WAL/journal files, blobs, and attachments.
- GTK recent-files data and file-picker history.
- Thumbnail and search-index services.
- Notification images and message previews.
- Spellcheck, input methods, clipboard managers, and accessibility tooling.
- Crash dumps, logs, telemetry, and support bundles.
- OS backups, snapshots, antivirus quarantine, swap, and hibernation.
- Temporary export/open-with files.

Move controllable caches into the encrypted mount or disable them. Document
the unavoidable OS-level residues accurately.

### 10. Test plan

Automated unit tests:

- Path normalization, nesting, Unicode, drive letters, and symlinks.
- State-machine transitions and stale async callbacks.
- CryFS exit-code mapping.
- Settings permissions and non-secret content.
- Password rejection for newline/empty input.
- Unmount binary discovery.

Integration tests with a fake CryFS:

- Password appears on stdin exactly once and nowhere else.
- stdout/stderr pipes are continuously drained.
- Slow startup, early exit, wrong password, timeout, and unmount failure.
- No accidental create during Unlock.
- UI cannot launch two owners.
- Closing is blocked while a child remains active.

Real CryFS tests:

- Create, write, random rewrite, rename, truncate, SQLite WAL, many small files,
  large attachments, `fsync`, and clean unmount.
- Verify plaintext names/content do not occur in the ciphertext tree.
- Power loss and process crash at controlled write points.
- Full disk, read-only vault, missing/corrupt blocks, changed config, rollback,
  and version upgrade.
- Busy file descriptors and strict unmount behavior.
- Idle unmount while consumers are active.
- Cross-version and cross-platform vault compatibility.

Security engineering:

- Fuzz path handling, process output, settings, and any future recovery format.
- Run ASan/UBSan where supported and static analysis on Vala-generated C.
- Independent code review focused on process ownership and secret lifetime.
- External cryptographic review before adding custom key envelopes.

### 11. Packaging and updates

- Reproducible release builds and CI artifacts for all target platforms.
- Signed binaries, notarized macOS app, and signed Windows driver/installers.
- Checksummed, signature-verified CryFS acquisition if managed by Parla.
- No network download from an unlock dialog.
- Clear separation between Parla version, SafeStore integration version, CryFS
  version, filesystem format, and driver version.
- A compatibility matrix and tested downgrade policy.
- An emergency disable/upgrade path for a CryFS security advisory.
- Licenses and source-offer obligations included in binary bundles.

### 12. Migration and rollout

Migration must be explicit and reversible:

1. Stop the RPC server.
2. Create and verify an empty encrypted vault.
3. Copy—not move—the existing accounts directory into the mounted view.
4. Flush, stop the consumer, and lock.
5. Reopen and validate all accounts and attachment samples.
6. Keep the original plaintext backup until the user confirms a separate
   encrypted backup and a successful recovery test.
7. Securely retire the old plaintext copy using platform-appropriate guidance;
   do not promise reliable deletion on SSDs or copy-on-write filesystems.

Roll out behind an experimental setting first. Collect only non-sensitive
failure categories, never paths, filenames, account identifiers, or process
output without explicit user review.

## Production-ready definition

The feature is ready for mainstream Parla only when:

- Stable CryFS and driver versions are pinned and supported on all advertised
  platforms.
- The full Parla/RPC lifecycle is transactional and race-tested.
- No known controllable plaintext spill remains outside the mount.
- Clean and busy unmount behavior is reliable.
- Crash, suspend, logout, shutdown, and upgrade paths are tested.
- A documented backup and independently usable recovery procedure exists.
- Security wording matches the tested threat model.
- Packaging, licensing, signatures, and updates are operational.
- External review has covered secret handling and any added key-management
  layer.
- Users can export/migrate their data without depending forever on Parla.

Until then, SafeStore should remain a disposable-data experiment.

## References

- [CryFS tutorial and operating-system overview](https://www.cryfs.org/tutorial)
- [CryFS encryption and configuration design](https://www.cryfs.org/howitworks)
- [CryFS stable releases](https://github.com/cryfs/cryfs/releases)
- [CryFS source repository](https://github.com/cryfs/cryfs)
- [CryFS comparison and metadata threat model](https://www.cryfs.org/comparison)
- [gocryptfs platform and security overview](https://github.com/rfjakob/gocryptfs)
- [rclone crypt format and key handling](https://rclone.org/crypt/)
- [EncFS security audit](https://defuse.ca/audits/encfs.htm)
- [NIST post-quantum cryptography FAQ](https://csrc.nist.gov/projects/post-quantum-cryptography/faqs)
