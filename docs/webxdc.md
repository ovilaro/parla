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

## How it works

The feature is isolated at file level: `src/webxdc.vala` holds the
jsonrpc plumbing and the JS bridge plus both view layers (an `#if MACOS`
picks NSWindow/WKWebView via `src/webxdc_macos.m`, otherwise
Adw.Window/WebKitGTK). When the option is off, `src/webxdc_stub.vala`
provides the same `Dc.Webxdc` entry points as no-ops, so no other file
needs conditional compilation and linking stays trivial.

- Apps appear in the chat as an accent-colored card and in the media
  gallery under **Apps**; both call `Webxdc.open ()`, one window per app
  instance. Nothing is automatic: the card first offers to download the
  `.xdc` archive (attachments beyond the auto-download limit stay on the
  server until then), then shows the app's real name and icon read from
  the archive, and starts it only on another explicit click.
- Besides the compile-time option there is a runtime switch: **Settings →
  Advanced → Webxdc apps** (`webxdc_apps` in `settings.ini`). Disabled,
  apps degrade to plain file attachments and the gallery refuses to
  launch them.
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
