# Webxdc apps (experimental)

[Webxdc](https://webxdc.org/) apps are tiny offline web apps (`.xdc` zip
archives) shared as Delta Chat attachments. Parla can run them in an
embedded WebKit view, but the feature is **off by default**: a web engine
is a browser-sized attack surface (and on Linux a large extra dependency),
so it will only be enabled once it has seen enough testing.

Two view backends share the same core:

- **GNOME/Linux**: [WebKitGTK](https://webkitgtk.org/) (`webkitgtk-6.0`).
- **macOS**: the system `WebKit.framework` (WKWebView) through a small
  ObjC shim — no WebKitGTK, no extra dependency, nothing to bundle.

## Building

```sh
make run WITH_WEBXDC=1     # macOS: works out of the box
                           # linux: needs webkitgtk-6.0 pkg-config
# or directly:
meson setup builddir -Dwebxdc=true
```

A plain `make` (or `-Dwebxdc=false`) reverts to the default build, which
links no web engine at all.

On native Linux installs, `sudo make install WITH_WEBXDC=1` also installs
and loads an AppArmor profile when AppArmor is active. This is needed on
Ubuntu 24.04 and newer, where the default user-namespace restriction can
otherwise prevent WebKitGTK's bubblewrap sandbox from starting. Systems
without AppArmor need no profile, staged package installs include it without
loading it on the build host, and Flatpak uses its own sandbox. See the
[README](../README.md#webxdc-apps-experimental) for platform support and
source-build caveats.

CI builds it in for macOS (system framework), the plain Linux build, the
.deb (depends on `libwebkitgtk-6.0-4`) and the Flatpak (WebKitGTK comes
with the GNOME runtime). The AppImage still ships the stub: bundling
WebKitGTK's helper processes into an AppImage is its own project. Users
can always turn apps off at runtime in Settings → Advanced.

## How it works

The feature is isolated at file level: `src/webxdc.vala` holds the
jsonrpc plumbing and the JS bridge plus both view layers (an `#if MACOS`
picks NSWindow/WKWebView via `src/webxdc_macos.m`, otherwise
Adw.Window/WebKitGTK). When the option is off, `src/webxdc_stub.vala`
provides the same `Dc.Webxdc` entry points as no-ops, so no other file
needs conditional compilation and linking stays trivial.

- Apps appear in the chat as an accent-colored card and in the media
  gallery under **Apps**. Clicking either opens the same dialog with
  **Start App**, **Download File**, and **Cancel**; starting or saving first
  fetches an archive that is beyond the auto-download limit. A downloaded
  card shows the app's real name and icon read from the archive. Running
  instances are still limited to one window per app.
- Besides the compile-time option there is a runtime switch: **Settings →
  Advanced → Webxdc apps** (`webxdc_apps` in `settings.ini`). Disabled,
  the app card stays recognizable and the dialog explains why it cannot
  start the app, offering only **Download File** and **Cancel**. Builds
  compiled without Webxdc support use the same download-only flow.
- Sending an `.xdc` file from Parla announces it with the `Webxdc`
  viewtype, so other clients show it as an app too.
- Every window gets its own isolated web context with a custom `webxdc:`
  URI scheme. Files are extracted from the `.xdc` archive by deltachat
  core (`get_webxdc_blob` over jsonrpc) — Parla never unzips anything
  itself and serves nothing from disk.
- `webxdc.js` is the one synthetic file: it installs `window.webxdc` and
  bridges to Vala through a WebKit script message handler.
- Status updates flow through the core jsonrpc calls
  `send_webxdc_status_update` / `get_webxdc_status_updates`; incoming
  `WebxdcStatusUpdate` events are routed to the matching open window,
  and `WebxdcInstanceDeleted` closes it.

## Security boundaries

Webxdc's contract is that apps run **offline and sandboxed**; Parla
enforces it inside the engine on both backends:

- **No network.** WebKitGTK: the `WebKit.NetworkSession` is ephemeral (no
  cookies or cache on disk) and configured with a blackhole SOCKS proxy,
  so any `http(s)` request an app attempts dies before reaching the
  network. macOS: a compiled `WKContentRuleList` blocks every load and
  then exempts only the `webxdc:` scheme, which covers subresource
  fetches too, with a non-persistent website data store. `webxdc:`
  content is served in-process and is unaffected either way.
- **No navigation escape.** The navigation policy delegate refuses any
  navigation or `window.open` outside the `webxdc:` scheme on both
  backends (macOS fails closed: if the rule list cannot compile, the web
  view is never created).
- **No filesystem.** All content comes from the archive via jsonrpc.
- **No persistence.** Ephemeral session: `localStorage` survives only as
  long as the window (a deliberate, safer deviation from the official
  client).
- Developer extras and modal dialogs are disabled.

## JS API exposed to apps

Only the core of the [official webxdc spec](https://webxdc.org/docs/spec/)
as used by the official Delta Chat clients — nothing else is injected:

| member | behaviour |
|---|---|
| `webxdc.selfAddr` | account address |
| `webxdc.selfName` | display name (falls back to the address) |
| `webxdc.sendUpdate(update, descr)` | `send_webxdc_status_update` |
| `webxdc.setUpdateListener(cb, serial)` | replays updates after `serial`, then live ones |

Optional spec extras (`sendToChat`, `importFiles`, `joinRealtimeChannel`)
are intentionally absent; apps must feature-detect them, and well-behaved
ones degrade gracefully.
